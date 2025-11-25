// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITKGasStation} from "gas-station/src/TKGasStation/interfaces/ITKGasStation.sol";
import {IBatchExecution} from "gas-station/src/TKGasStation/interfaces/IBatchExecution.sol";
import {ITKGasDelegate} from "gas-station/src/TKGasStation/interfaces/ITKGasDelegate.sol";
import {IsDelegated} from "./IsDelegated.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

abstract contract AbstractReimbursableGasStation {
    error NotDelegated();
    error InvalidSessionSignature();
    error InsufficientBalance();
    error GasLimitExceeded();

    error r(uint256 a);

    event GasReimbursed(uint256 gasUsed, uint256 reimbursementAmount, address from, address destination);
    event GasChangeReturned(uint256 gasChange, address target);
    event ExecutionFailed(address target, address to, uint256 ethAmount, bytes data);
    event TransferFailed(address to, uint256 amount);
    event TransferFailedUnclaimedStored(address to, uint256 amount);
    event GasPulled(uint256 gasLimit, address target);

    address public immutable TK_GAS_DELEGATE;
    address public immutable REIMBURSEMENT_ADDRESS;
    address public immutable REIMBURSEMENT_ERC20;
    uint16 public immutable GAS_FEE_BASIS_POINTS;
    uint256 public immutable BASE_GAS_FEE_ERC20;
    uint256 public immutable MAX_GAS_LIMIT_ERC20;
    IERC20 public immutable REIMBURSEMENT_ERC20_TOKEN;

    mapping(address => uint256) public unclaimedGasReimbursements;

    constructor(
        address _tkGasDelegate,
        address _reimbursementAddress,
        address _reimbursementErc20,
        uint16 _gasFeeBasisPoints,
        uint256 _minimumGasFee,
        uint256 _maxGasLimit
    ) {
        TK_GAS_DELEGATE = _tkGasDelegate;
        REIMBURSEMENT_ADDRESS = _reimbursementAddress;
        REIMBURSEMENT_ERC20 = _reimbursementErc20;
        REIMBURSEMENT_ERC20_TOKEN = IERC20(_reimbursementErc20);
        GAS_FEE_BASIS_POINTS = _gasFeeBasisPoints;
        BASE_GAS_FEE_ERC20 = _minimumGasFee;
        MAX_GAS_LIMIT_ERC20 = _maxGasLimit;
    }

    function _isDelegated(address _targetEoA) internal view returns (bool) {
        return IsDelegated._isdelegated(_targetEoA, TK_GAS_DELEGATE);
    }

    function _checkOnlyDelegated(address _targetEoA) internal view {
        if (!_isDelegated(_targetEoA)) {
            revert NotDelegated();
        }
    }

    function _checkWithinGasLimit(uint256 _gasLimit) internal view {
        if (_gasLimit > MAX_GAS_LIMIT_ERC20) {
            revert GasLimitExceeded();
        }
    }

    function _verifyPackedSessionSignatureData(
        bytes calldata _packedSessionSignatureData
    ) internal pure  {
        if (_packedSessionSignatureData.length != 85) {
            revert InvalidSessionSignature();
        }
    }
    
    function _setupInitialGasPull(uint256 _gasLimitERC20, bytes calldata _packedSessionSignatureData, address _target) internal returns (uint256 gasStart) {
        gasStart = _initGasAndValidate(_gasLimitERC20, _packedSessionSignatureData, _target);
        uint256 startBalance = REIMBURSEMENT_ERC20_TOKEN.balanceOf(address(this));
        // This function works by pulling the entire gas limit from the user in erc20 tokens, then paying back the unused gas
        bytes memory transferGasLimitData =
            abi.encodeWithSelector(IERC20.transfer.selector, address(this), _gasLimitERC20);
        bytes memory data = abi.encodePacked(_packedSessionSignatureData, transferGasLimitData);
        ITKGasDelegate(_target).executeSession(REIMBURSEMENT_ERC20, 0, data);

        if (REIMBURSEMENT_ERC20_TOKEN.balanceOf(address(this)) < _gasLimitERC20) {
            revert InsufficientBalance(); // The paymaster can lose money on this revert
        } else {
            emit GasPulled(_gasLimitERC20, _target);
        }
    }

    function _initGasAndValidate(uint256 _gasLimitERC20, bytes calldata _packedSessionSignatureData, address _target) internal returns (uint256) {
        uint256 gasStart = gasleft();
        _checkOnlyDelegated(_target);
        _checkWithinGasLimit(_gasLimitERC20);
        _verifyPackedSessionSignatureData(_packedSessionSignatureData);
        return gasStart;
    }

    function _calculateReimbursementAmount(uint256 _gasStart) internal returns (uint256, uint256) {
        uint256 gasUsed = _gasStart - gasleft();
        gasUsed += (gasUsed * GAS_FEE_BASIS_POINTS / 10000);

        return (gasUsed, _convertGasToERC20(gasUsed) + BASE_GAS_FEE_ERC20);
    }

    function _reimburseGas(uint256 _gasStart, uint256 _gasLimitERC20, bytes calldata _packedSessionSignatureData, address _target) internal {
        (uint256 gasUsed, uint256 reimbursementAmountERC20) = _calculateReimbursementAmount(_gasStart);

        if (reimbursementAmountERC20 > _gasLimitERC20) {
            // Reimburse up to the limit if the gas limit is exceeded. The paymaster can lose money on this
            // The paymaster should set sane limits to avoid this
            (bool limitReimbursementSuccess,) = REIMBURSEMENT_ERC20.call(
                abi.encodeWithSelector(IERC20.transfer.selector, REIMBURSEMENT_ADDRESS, _gasLimitERC20)
            );
            if (limitReimbursementSuccess) {
                emit GasReimbursed(gasUsed, _gasLimitERC20, _target, REIMBURSEMENT_ADDRESS);
            } else {
                unclaimedGasReimbursements[REIMBURSEMENT_ADDRESS] += _gasLimitERC20;
                emit TransferFailedUnclaimedStored(REIMBURSEMENT_ADDRESS, _gasLimitERC20);
            }

            // Then we attempt to pay the excess to the reimbursement address, but there is no guarantee it will succeed
            bytes memory transferExcessData = abi.encodeWithSelector(
                IERC20.transfer.selector, REIMBURSEMENT_ADDRESS, _gasLimitERC20 - reimbursementAmountERC20
            );
            bytes memory excessData = abi.encodePacked(_packedSessionSignatureData, transferExcessData);
            try ITKGasDelegate(_target).executeSession(REIMBURSEMENT_ERC20, 0, excessData) {
                // Transfer succeeded
                emit GasReimbursed(gasUsed, _gasLimitERC20 - reimbursementAmountERC20, _target, REIMBURSEMENT_ADDRESS);
            } catch {
                emit TransferFailed(REIMBURSEMENT_ADDRESS, _gasLimitERC20 - reimbursementAmountERC20);
            }
        } else { 
            // Otherwise return the change to the user

            (bool reimbursementSuccess,) = REIMBURSEMENT_ERC20.call(
                abi.encodeWithSelector(IERC20.transfer.selector, REIMBURSEMENT_ADDRESS, reimbursementAmountERC20)
            );
            if (reimbursementSuccess) {
                emit GasReimbursed(gasUsed, reimbursementAmountERC20, _target, REIMBURSEMENT_ADDRESS);
            } else {
                unclaimedGasReimbursements[REIMBURSEMENT_ADDRESS] += reimbursementAmountERC20;
                emit TransferFailedUnclaimedStored(REIMBURSEMENT_ADDRESS, reimbursementAmountERC20);
            }

            uint256 amountToReturn = _gasLimitERC20 - reimbursementAmountERC20;

            // Transfer the refund directly from the gas station to the user
            // Use a low-level call to allow try-catch on the transfer
            if (amountToReturn > 0) {
            (bool success,) =
                    REIMBURSEMENT_ERC20.call(abi.encodeWithSelector(IERC20.transfer.selector, _target, amountToReturn));
                if (!success) {
                    // emit event for failed transfer
                    unclaimedGasReimbursements[_target] += amountToReturn;
                    emit TransferFailedUnclaimedStored(_target, amountToReturn);
                } else {
                    emit GasChangeReturned(amountToReturn, _target);
                }
            }
        }
    }

    function _convertGasToERC20(uint256 _gasAmount) internal virtual returns (uint256);

    // Execute functions
    function executeReturns(
        uint256 _gasLimitERC20,
        bytes calldata _packedSessionSignatureData,
        address _target,
        address _to,
        uint256 _ethAmount,
        bytes calldata _data
    ) external returns (bytes memory result) {
 
        uint256 gasStart = _setupInitialGasPull(_gasLimitERC20, _packedSessionSignatureData, _target);
 
        try ITKGasDelegate(_target).executeReturns(_to, _ethAmount, _data) returns (bytes memory res) {
            result = res;
        } catch {
            // emit event for failed execution
            emit ExecutionFailed(_target, _to, _ethAmount, _data);
        }

        _reimburseGas(gasStart, _gasLimitERC20, _packedSessionSignatureData, _target);
        
    }

    function claimUnclaimedGasReimbursements() external {
        uint256 amountToClaim = unclaimedGasReimbursements[msg.sender];
        if (amountToClaim == 0) {
            revert InsufficientBalance();
        }
        unclaimedGasReimbursements[msg.sender] = 0;
        SafeTransferLib.safeTransfer(REIMBURSEMENT_ERC20, msg.sender, amountToClaim);
    }

    function burnNonce(address _targetEoA, bytes calldata _signature, uint128 _nonce)
        external
    {
        _checkOnlyDelegated(_targetEoA);
        ITKGasDelegate(_targetEoA).burnNonce(_signature, _nonce);
    }

    function getNonce(address _targetEoA) external view returns (uint128) {
        return ITKGasDelegate(_targetEoA).nonce();
    }

    function isDelegated(address _targetEoA) external view returns (bool) {
        return _isDelegated(_targetEoA);
    }
}
