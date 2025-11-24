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
    event ExecutionFailed(address target, address to, uint256 ethAmount, bytes data);
    event TransferFailed(address to, uint256 amount);

    address public immutable TK_GAS_DELEGATE;
    address public immutable REIMBURSEMENT_ADDRESS;
    address public immutable REIMBURSEMENT_ERC20;
    uint16 public immutable GAS_FEE_BASIS_POINTS;
    uint256 public immutable BASE_GAS_FEE_ERC20;
    uint256 public immutable MAX_GAS_LIMIT_ERC20;
    IERC20 public immutable REIMBURSEMENT_ERC20_TOKEN;

    mapping(address => bytes) public cachedPackedSessionSignatureData;
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

    modifier onlyDelegated(address _targetEoA) {
        if (!_isDelegated(_targetEoA)) {
            revert NotDelegated();
        }
        _;
    }

    modifier withinGasLimit(uint256 _gasLimit) {
        if (_gasLimit > MAX_GAS_LIMIT_ERC20) {
            revert GasLimitExceeded();
        }
        _;
    }

    function _getOrInsertCachedPackedSessionSignatureData(
        address _targetEoA,
        bytes calldata _packedSessionSignatureData
    ) internal returns (bytes memory) {
        bytes memory toReturn;
        if (_packedSessionSignatureData.length == 0) {
            toReturn = cachedPackedSessionSignatureData[_targetEoA];
        } else {
            toReturn = _packedSessionSignatureData;
            cachedPackedSessionSignatureData[_targetEoA] = _packedSessionSignatureData;
        }
        if (toReturn.length != 85) {
            revert InvalidSessionSignature();
        }
        return toReturn;
    }
    //function _gasToReimburseInERC20(uint256 _gasAmount, bool _returns) internal virtual returns (uint256);

    function _convertGasToERC20(uint256 _gasAmount) internal virtual returns (uint256);

    // todo: use transient storage to cache gas amount

    // Execute functions
    function executeReturns(
        uint256 _gasLimitERC20,
        address _target,
        address _to,
        uint256 _ethAmount,
        bytes calldata _packedSessionSignatureData,
        bytes calldata _data
    ) external onlyDelegated(_target) withinGasLimit(_gasLimitERC20) returns (bytes memory) {
        uint256 gasStart = gasleft();

        bytes memory packedSessionSignatureData =
            _getOrInsertCachedPackedSessionSignatureData(_target, _packedSessionSignatureData);

        uint256 startBalance = REIMBURSEMENT_ERC20_TOKEN.balanceOf(address(this));
        // This function works by pulling the entire gas limit from the user in erc20 tokens, then paying back the unused gas
        bytes memory transferGasLimitData =
            abi.encodeWithSelector(IERC20.transfer.selector, address(this), _gasLimitERC20);
        bytes memory data = abi.encodePacked(packedSessionSignatureData, transferGasLimitData);
        ITKGasDelegate(_target).executeSession(REIMBURSEMENT_ERC20, 0, data);
        if (REIMBURSEMENT_ERC20_TOKEN.balanceOf(address(this)) - startBalance < _gasLimitERC20) {
            revert InsufficientBalance(); // The paymaster can lose money on this revert
        }
        bytes memory result = "";
        try ITKGasDelegate(_target).executeReturns(_to, _ethAmount, _data) returns (bytes memory res) {
            result = res;
        } catch {
            // emit event for failed execution
            emit ExecutionFailed(_target, _to, _ethAmount, _data);
        }
        uint256 gasUsed = gasStart - gasleft();
        gasUsed += (gasUsed * GAS_FEE_BASIS_POINTS / 10000);

        uint256 reimbursementAmountERC20 = _convertGasToERC20(gasUsed) + BASE_GAS_FEE_ERC20;

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
                emit TransferFailed(REIMBURSEMENT_ADDRESS, _gasLimitERC20);
            }

            // Then we attempt to pay the excess to the reimbursement address, but there is no guarantee it will succeed
            bytes memory transferExcessData = abi.encodeWithSelector(
                IERC20.transfer.selector, REIMBURSEMENT_ADDRESS, _gasLimitERC20 - reimbursementAmountERC20
            );
            bytes memory excessData = abi.encodePacked(packedSessionSignatureData, transferExcessData);
            try ITKGasDelegate(_target).executeSession(REIMBURSEMENT_ERC20, 0, excessData) {
                // Transfer succeeded
                emit GasReimbursed(gasUsed, _gasLimitERC20 - reimbursementAmountERC20, _target, REIMBURSEMENT_ADDRESS);
            } catch {
                emit TransferFailed(REIMBURSEMENT_ADDRESS, _gasLimitERC20 - reimbursementAmountERC20);
            }
            return result;
        } else { 
            // Otherwise return the change to the user

            (bool reimbursementSuccess,) = REIMBURSEMENT_ERC20.call(
                abi.encodeWithSelector(IERC20.transfer.selector, REIMBURSEMENT_ADDRESS, reimbursementAmountERC20)
            );
            if (reimbursementSuccess) {
                emit GasReimbursed(gasUsed, reimbursementAmountERC20, _target, REIMBURSEMENT_ADDRESS);
            } else {
                unclaimedGasReimbursements[REIMBURSEMENT_ADDRESS] += reimbursementAmountERC20;
                emit TransferFailed(REIMBURSEMENT_ADDRESS, reimbursementAmountERC20);
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
                    emit TransferFailed(_target, amountToReturn);
                }
            }
            return result;
        }
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
        onlyDelegated(_targetEoA)
    {
        ITKGasDelegate(_targetEoA).burnNonce(_signature, _nonce);
    }

    function getNonce(address _targetEoA) external view returns (uint128) {
        return ITKGasDelegate(_targetEoA).nonce();
    }

    function isDelegated(address _targetEoA) external view returns (bool) {
        return _isDelegated(_targetEoA);
    }
}
