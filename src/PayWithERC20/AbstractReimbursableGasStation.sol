// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IBatchExecution} from "gas-station/src/TKGasStation/interfaces/IBatchExecution.sol";
import {ITKGasDelegate} from "gas-station/src/TKGasStation/interfaces/ITKGasDelegate.sol";
import {IsDelegated} from "../IsDelegated.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

abstract contract AbstractReimbursableGasStation {
    error NotDelegated();
    error InvalidSessionSignature();
    error InsufficientBalance();
    error GasLimitExceeded();

    event GasReimbursed(address _from, address _destination, uint256 _gasUsed, uint256 _reimbursementAmount);
    event GasChangeReturned(address _target, uint256 _gasChange);
    event ExecutionFailed(address _target, address _to, uint256 _ethAmount, bytes _data);
    event BatchExecutionFailed(address _target, uint256 _callsLength);
    event ApproveThenExecuteFailed(
        address _target,
        address _to,
        uint256 _ethAmount,
        address _erc20,
        address _spender,
        uint256 _approveAmount,
        bytes _data
    );
    event TransferFailed(address _to, uint256 _amount);
    event TransferFailedUnclaimedStored(address _to, uint256 _amount);
    event GasPulled(address _from, uint256 _gasLimit);
    event GasUnpaid(address _from, uint256 _amount);

    uint16 public immutable GAS_FEE_BASIS_POINTS;
    bool public immutable ERC20_TRANSFER_SUCCEEDED_RETURN_DATA_CHECK;
    address public immutable TK_GAS_DELEGATE;
    address public immutable REIMBURSEMENT_ADDRESS;
    address public immutable REIMBURSEMENT_ERC20;
    uint256 public immutable BASE_GAS_FEE_ERC20;
    uint256 public immutable MAX_GAS_LIMIT_ERC20;
    IERC20 public immutable REIMBURSEMENT_ERC20_TOKEN;

    mapping(address => uint256) public unclaimedGasReimbursements;

    struct ApproveThenExecuteParams {
        address to;
        uint256 ethAmount;
        address erc20;
        address spender;
        uint256 approveAmount;
        bytes data;
    }

    constructor(
        address _tkGasDelegate,
        address _reimbursementAddress,
        address _reimbursementErc20,
        uint16 _gasFeeBasisPoints,
        bool _erc20TransferSucceededReturnDataCheck, // only set to true if you need to check the return data (does not revert on failure)
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
        ERC20_TRANSFER_SUCCEEDED_RETURN_DATA_CHECK = _erc20TransferSucceededReturnDataCheck;
    }

    function _convertGasToERC20(uint256 _gasAmount) internal virtual returns (uint256);

    function _transferReimbursementERC20(address _to, uint256 _amount) internal returns (bool) {
        (bool success, bytes memory returnData) = REIMBURSEMENT_ERC20.call(
            abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount)
        );
        if(ERC20_TRANSFER_SUCCEEDED_RETURN_DATA_CHECK){ // only needed for non-standard erc-20 tokens that don't revert on failure to transfer
            return success && (returnData.length == 0 || abi.decode(returnData, (bool)));
        } else {
            return success; 
        }
    }

    function _trySessionTransfer(address _from, address _token, address _destination, uint256 _amount, bytes calldata _packedSessionSignatureData) internal returns (bool success) {
        bytes memory data = _encodeForSessionBasedTransfer(_destination, _amount, _packedSessionSignatureData);
        try ITKGasDelegate(_from).executeSessionReturns(_token, 0, data) returns (bytes memory returnData) {
            if (ERC20_TRANSFER_SUCCEEDED_RETURN_DATA_CHECK && returnData.length > 0) {
                success = abi.decode(returnData, (bool));
            } else {
                success = true;
            }
        } catch {
            success = false;
        }
    }

    function _encodeForSessionBasedTransfer(address _to, uint256 _amount, bytes calldata _packedSessionSignatureData) internal pure returns (bytes memory) {
        bytes memory transferData =
            abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount);
        return abi.encodePacked(_packedSessionSignatureData, transferData);
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
        bool transferSucceeded = _trySessionTransfer(_target, REIMBURSEMENT_ERC20, address(this), _gasLimitERC20, _packedSessionSignatureData);
        if (!transferSucceeded || REIMBURSEMENT_ERC20_TOKEN.balanceOf(address(this)) - startBalance < _gasLimitERC20) {
            revert InsufficientBalance(); // The paymaster can lose money on this revert
        } else {
            emit GasPulled(_target, _gasLimitERC20);
        }
    }

    function _initGasAndValidate(uint256 _gasLimitERC20, bytes calldata _packedSessionSignatureData, address _target) internal view returns (uint256) {
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
            bool limitReimbursementSuccess = _transferReimbursementERC20(REIMBURSEMENT_ADDRESS, _gasLimitERC20);
            if (limitReimbursementSuccess) {
                emit GasReimbursed(_target, REIMBURSEMENT_ADDRESS, gasUsed, _gasLimitERC20);
            } else {
                unclaimedGasReimbursements[REIMBURSEMENT_ADDRESS] += _gasLimitERC20;
                emit TransferFailedUnclaimedStored(REIMBURSEMENT_ADDRESS, _gasLimitERC20);
            }

            uint256 excessAmount = reimbursementAmountERC20 - _gasLimitERC20;
            // Then we attempt to pay the excess to the reimbursement address, but there is no guarantee it will succeed
            bool transferSucceeded = _trySessionTransfer(_target, REIMBURSEMENT_ERC20, REIMBURSEMENT_ADDRESS, excessAmount, _packedSessionSignatureData);
            if (transferSucceeded) {
                // Transfer succeeded
                emit GasReimbursed(_target, REIMBURSEMENT_ADDRESS, gasUsed, excessAmount);
            } else {
                emit GasUnpaid(REIMBURSEMENT_ADDRESS, excessAmount); // One state where the user abused the paymaster
            }
        } else { 
            // Otherwise return the change to the user
            bool reimbursementSuccess = _transferReimbursementERC20(REIMBURSEMENT_ADDRESS, reimbursementAmountERC20);
            if (reimbursementSuccess) {
                emit GasReimbursed(_target, REIMBURSEMENT_ADDRESS, gasUsed, reimbursementAmountERC20);
            } else {
                unclaimedGasReimbursements[REIMBURSEMENT_ADDRESS] += reimbursementAmountERC20;
                emit TransferFailedUnclaimedStored(REIMBURSEMENT_ADDRESS, reimbursementAmountERC20);
            }

            uint256 amountToReturn = _gasLimitERC20 - reimbursementAmountERC20;

            // Transfer the refund directly from the gas station to the user
            // Use a low-level call to allow try-catch on the transfer
            if (amountToReturn > 0) {
                bool transferSucceeded = _transferReimbursementERC20(_target, amountToReturn);
                if (transferSucceeded) {
                    emit GasChangeReturned(_target, amountToReturn);
                } else {
                    // emit event for failed transfer
                    unclaimedGasReimbursements[_target] += amountToReturn;
                    emit TransferFailedUnclaimedStored(_target, amountToReturn);
                }
            }
        }
    }

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

    // Execute function (no return)
    function execute(
        uint256 _gasLimitERC20,
        bytes calldata _packedSessionSignatureData,
        address _target,
        address _to,
        uint256 _ethAmount,
        bytes calldata _data
    ) external {
        uint256 gasStart = _setupInitialGasPull(_gasLimitERC20, _packedSessionSignatureData, _target);

        try ITKGasDelegate(_target).execute(_to, _ethAmount, _data) {
            // Execution succeeded
        } catch {
            // emit event for failed execution
            emit ExecutionFailed(_target, _to, _ethAmount, _data);
        }

        _reimburseGas(gasStart, _gasLimitERC20, _packedSessionSignatureData, _target);
    }

    // ApproveThenExecute functions
    function approveThenExecute(
        uint256 _gasLimitERC20,
        bytes calldata _packedSessionSignatureData,
        address _target,
        address _to,
        uint256 _ethAmount,
        address _erc20,
        address _spender,
        uint256 _approveAmount,
        bytes calldata _data
    ) external {
        ApproveThenExecuteParams memory p = ApproveThenExecuteParams(_to, _ethAmount, _erc20, _spender, _approveAmount, _data);
        uint256 g = _setupInitialGasPull(_gasLimitERC20, _packedSessionSignatureData, _target);
        try ITKGasDelegate(_target).approveThenExecute(p.to, p.ethAmount, p.erc20, p.spender, p.approveAmount, p.data) {
        } catch {
            emit ApproveThenExecuteFailed(_target, p.to, p.ethAmount, p.erc20, p.spender, p.approveAmount, p.data);
        }
        _reimburseGas(g, _gasLimitERC20, _packedSessionSignatureData, _target);
    }

    function approveThenExecuteReturns(
        uint256 _gasLimitERC20,
        bytes calldata _packedSessionSignatureData,
        address _target,
        address _to,
        uint256 _ethAmount,
        address _erc20,
        address _spender,
        uint256 _approveAmount,
        bytes calldata _data
    ) external returns (bytes memory result) {
        ApproveThenExecuteParams memory p = ApproveThenExecuteParams(_to, _ethAmount, _erc20, _spender, _approveAmount, _data);
        uint256 g = _setupInitialGasPull(_gasLimitERC20, _packedSessionSignatureData, _target);
        try ITKGasDelegate(_target).approveThenExecuteReturns(p.to, p.ethAmount, p.erc20, p.spender, p.approveAmount, p.data) returns (bytes memory res) {
            result = res;
        } catch {
            emit ApproveThenExecuteFailed(_target, p.to, p.ethAmount, p.erc20, p.spender, p.approveAmount, p.data);
        }
        _reimburseGas(g, _gasLimitERC20, _packedSessionSignatureData, _target);
    }

    // Batch execute functions
    function executeBatch(
        uint256 _gasLimitERC20,
        bytes calldata _packedSessionSignatureData,
        address _target,
        IBatchExecution.Call[] calldata _calls,
        bytes calldata _data
    ) external {
        uint256 gasStart = _setupInitialGasPull(_gasLimitERC20, _packedSessionSignatureData, _target);

        try ITKGasDelegate(_target).executeBatch(_calls, _data) {
            // Execution succeeded
        } catch {
            // emit event for failed batch execution
            emit BatchExecutionFailed(_target, _calls.length);
        }

        _reimburseGas(gasStart, _gasLimitERC20, _packedSessionSignatureData, _target);
    }

    function executeBatchReturns(
        uint256 _gasLimitERC20,
        bytes calldata _packedSessionSignatureData,
        address _target,
        IBatchExecution.Call[] calldata _calls,
        bytes calldata _data
    ) external returns (bytes[] memory result) {
        uint256 gasStart = _setupInitialGasPull(_gasLimitERC20, _packedSessionSignatureData, _target);

        try ITKGasDelegate(_target).executeBatchReturns(_calls, _data) returns (bytes[] memory res) {
            result = res;
        } catch {
            // emit event for failed batch execution
            emit BatchExecutionFailed(_target, _calls.length);
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

    function burnNonce(
        uint256 _gasLimitERC20,
        bytes calldata _packedSessionSignatureData,
        address _targetEoA,
        bytes calldata _signature,
        uint128 _nonce
    ) external {
        uint256 gasStart = _setupInitialGasPull(_gasLimitERC20, _packedSessionSignatureData, _targetEoA);

        try ITKGasDelegate(_targetEoA).burnNonce(_signature, _nonce) {
            // Burn succeeded
        } catch {
            // emit event for failed execution
            emit ExecutionFailed(_targetEoA, address(0), 0, "");
        }

        _reimburseGas(gasStart, _gasLimitERC20, _packedSessionSignatureData, _targetEoA);
    }

    function burnCounter(
        uint256 _gasLimitERC20,
        bytes calldata _packedSessionSignatureData,
        address _targetEoA,
        bytes calldata _signature,
        uint128 _counter
    ) external {
        uint256 gasStart = _setupInitialGasPull(_gasLimitERC20, _packedSessionSignatureData, _targetEoA);

        try ITKGasDelegate(_targetEoA).burnSessionCounter(_signature, _counter) {
            // Burn succeeded
        } catch {
            // emit event for failed execution
            emit ExecutionFailed(_targetEoA, address(0), 0, "");
        }

        _reimburseGas(gasStart, _gasLimitERC20, _packedSessionSignatureData, _targetEoA);
    }

    function getNonce(address _targetEoA) external view returns (uint128) {
        return ITKGasDelegate(_targetEoA).nonce();
    }

    function isDelegated(address _targetEoA) external view returns (bool) {
        return _isDelegated(_targetEoA);
    }
}

