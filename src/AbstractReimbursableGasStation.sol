// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITKGasStation} from "gas-station/src/TKGasStation/interfaces/ITKGasStation.sol";
import {IBatchExecution} from "gas-station/src/TKGasStation/interfaces/IBatchExecution.sol";
import {ITKGasDelegate} from "gas-station/src/TKGasStation/interfaces/ITKGasDelegate.sol";
import {IsDelegated} from "./IsDelegated.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";


abstract contract AbstractReimbursableGasStation is ITKGasStation {
    error NotDelegated();
    error TransferFailed();

    address public immutable TK_GAS_DELEGATE;
    address public immutable REIMBURSEMENT_ADDRESS;
    address public immutable REIMBURSEMENT_ERC20;

    constructor(address _tkGasDelegate, address _reimbursementAddress, address _reimbursementErc20) {
        TK_GAS_DELEGATE = _tkGasDelegate;
        REIMBURSEMENT_ADDRESS = _reimbursementAddress;
        REIMBURSEMENT_ERC20 = _reimbursementErc20;
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

    function _gasToReimburseInERC20(uint256 _gasAmount, bool _returns) internal virtual returns (uint256);

    // Execute functions
    function executeReturns(address _target, address _to, uint256 _ethAmount, bytes calldata _data)
        external
        override
        onlyDelegated(_target)
        returns (bytes memory)
    {
        uint256 gasStart = gasleft();
        bytes memory result = ITKGasDelegate(_target).executeReturns(_to, _ethAmount, _data);
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasStart - gasleft(), true);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        return result;
    }

    function execute(address _target, address _to, uint256 _ethAmount, bytes calldata _data) external onlyDelegated(_target) override {
        uint256 gasStart = gasleft();
        ITKGasDelegate(_target).execute(_to, _ethAmount, _data);
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasStart - gasleft(), false);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
    }

    // ApproveThenExecute functions
    function approveThenExecuteReturns(
        address _target,
        address _to,
        uint256 _ethAmount,
        address _erc20,
        address _spender,
        uint256 _approveAmount,
        bytes calldata _data
    ) external onlyDelegated(_target) override returns (bytes memory) {
        uint256 gasStart = gasleft();
        bytes memory result = ITKGasDelegate(_target).approveThenExecuteReturns(_to, _ethAmount, _erc20, _spender, _approveAmount, _data);
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasStart - gasleft(), true);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        return result;
    }

    function approveThenExecute(
        address _target,
        address _to,
        uint256 _ethAmount,
        address _erc20,
        address _spender,
        uint256 _approveAmount,
        bytes calldata _data
    ) external onlyDelegated(_target) override {
        uint256 gasStart = gasleft();
        ITKGasDelegate(_target).approveThenExecute(_to, _ethAmount, _erc20, _spender, _approveAmount, _data);
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasStart - gasleft(), false);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
    }

    // Batch execute functions
    function executeBatchReturns(address _target, IBatchExecution.Call[] calldata _calls, bytes calldata _data)
        external
        onlyDelegated(_target)
        override
        returns (bytes[] memory)
    {
        uint256 gasStart = gasleft();
        bytes[] memory results = ITKGasDelegate(_target).executeBatchReturns(_calls, _data);
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasStart - gasleft(), true);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        return results;
    }

    function executeBatch(address _target, IBatchExecution.Call[] calldata _calls, bytes calldata _data)
        external
        onlyDelegated(_target)
        override
    {
        uint256 gasStart = gasleft();
        ITKGasDelegate(_target).executeBatch(_calls, _data);
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasStart - gasleft(), false);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
    }

    function burnNonce(address _targetEoA, bytes calldata _signature, uint128 _nonce) external onlyDelegated(_targetEoA) override {
        ITKGasDelegate(_targetEoA).burnNonce(_signature, _nonce);
    }

    function getNonce(address _targetEoA) external view override returns (uint128) {
        return ITKGasDelegate(_targetEoA).nonce();
    }

    function isDelegated(address _targetEoA) external view override returns (bool) {
        return _isDelegated(_targetEoA);
    }
}
