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
    error TransferFailed();
    error InvalidSessionSignature();
    error InsufficientBalance();

    event GasReimbursed(uint256 gasUsed, uint256 reimbursementAmount, address from, address destination);
    event ExecutionFailed(address target, address to, uint256 ethAmount, bytes data);
    event TransferFailed(address to, uint256 amount);

    address public immutable TK_GAS_DELEGATE;
    address public immutable REIMBURSEMENT_ADDRESS;
    address public immutable REIMBURSEMENT_ERC20;
    uint16 public immutable GAS_FEE_BASIS_POINTS;
    uint256 public immutable BASE_GAS_FEE; 
    IERC20 public immutable REIMBURSEMENT_ERC20_TOKEN;

    mapping(address => bytes) public cachedPackedSessionSignatureData;
    mapping(address => uint256) public unclaimedGasReimbursements;

    constructor(address _tkGasDelegate, address _reimbursementAddress, address _reimbursementErc20, uint16 _gasFeeBasisPoints, uint256 _minimumGasFee) {
        TK_GAS_DELEGATE = _tkGasDelegate;
        REIMBURSEMENT_ADDRESS = _reimbursementAddress;
        REIMBURSEMENT_ERC20 = _reimbursementErc20;
        REIMBURSEMENT_ERC20_TOKEN = IERC20(_reimbursementErc20);
        GAS_FEE_BASIS_POINTS = _gasFeeBasisPoints;
        BASE_GAS_FEE = _minimumGasFee;
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

    modifier onlyValidSessionSignature(bytes calldata _packedSessionSignatureData, address _targetEoA) {
        if (_packedSessionSignatureData.length != 85 || cachedPackedSessionSignatureData[_targetEoA] != _packedSessionSignatureData) {
            revert InvalidSessionSignature();
        }
        _;
    }

    function _getOrInsertCachedPackedSessionSignatureData(address _targetEoA, bytes calldata _packedSessionSignatureData) internal view returns (bytes memory) {
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
    function executeReturns(address _target, address _to, uint256 _ethAmount, bytes calldata _packedSessionSignatureData, bytes calldata _data)
        external
        onlyDelegated(_target)
        returns (bytes memory)
    {
        uint256 gasStart = gasleft();

        bytes memory packedSessionSignatureData = _getOrInsertCachedPackedSessionSignatureData(_target, _packedSessionSignatureData);
        uint256 totalGasLimitERC20 = _convertGasToERC20(tx.gaslimit);

        bytes memory transferGasLimitData = abi.encodeWithSelector(_IERC20.transfer.selector, address(this), totalGasLimitERC20);
        bytes memory data = abi.encodePacked(packedSessionSignatureData, transferGasLimitData);
        ITKGasDelegate(_target).executeSession(REIMBURSEMENT_ADDRESS, 0, data);
        if(REIMBURSEMENT_ERC20_TOKEN.balanceOf(address(this)) < totalGasLimitERC20) {
            revert InsufficientBalance(); // only revert where the paymaster can lose money
        }

        bytes memory result = "";
        try ITKGasDelegate(_target).executeReturns(_to, _ethAmount, _data) returns (bytes memory res) {
            result = res;
        } catch {
            // emit event for failed execution
            emit ExecutionFailed(_target, _to, _ethAmount, _data);
        }
        uint256 gasUsed = gasStart - gasleft();
        gasUsed += (gasUsed * GAS_FEE_BASIS_POINTS / 10000) + BASE_GAS_FEE;
        uint256 reimbursementAmountERC20 = _convertGasToERC20(gasUsed);

        SafeTransferLib.transfer(REIMBURSEMENT_ERC20, REIMBURSEMENT_ADDRESS, reimbursementAmountERC20);
        emit GasReimbursed(gasUsed, reimbursementAmountERC20, _target, REIMBURSEMENT_ADDRESS);

        uint256 amountToReturn = totalGasLimitERC20 - reimbursementAmountERC20;

        try SafeTransferLib.transfer(REIMBURSEMENT_ERC20, _target, amountToReturn) { // this is so the transfer can't grief the paymaster by reverting
        } catch {
            // emit event for failed transfer
            unclaimedGasReimbursements[_target] += amountToReturn;
            emit TransferFailed(_target, amountToReturn);
        }
        return result;

        /*
        uint256 gasStart = gasleft();
        bytes memory result = ITKGasDelegate(_target).executeReturns(_to, _ethAmount, _data);
        uint256 gasUsed = gasStart - gasleft();
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasUsed, true);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        emit GasReimbursed(gasUsed, reimbursementAmount, _target, REIMBURSEMENT_ADDRESS);
        return result;
        */
    }

    function claimUnclaimedGasReimbursements() external {
        uint256 amountToClaim = unclaimedGasReimbursements[msg.sender];
        if (amountToClaim == 0) {
            revert InsufficientBalance();
        }
        unclaimedGasReimbursements[msg.sender] = 0;
        SafeTransferLib.transfer(REIMBURSEMENT_ERC20, msg.sender, amountToClaim);
    }
/*
    function execute(address _target, address _to, uint256 _ethAmount, bytes calldata _data) external onlyDelegated(_target) override {
        uint256 gasStart = gasleft();
        ITKGasDelegate(_target).execute(_to, _ethAmount, _data);
        uint256 gasUsed = gasStart - gasleft();
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasUsed, false);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        emit GasReimbursed(gasUsed, reimbursementAmount, _target, REIMBURSEMENT_ADDRESS);
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
        uint256 gasUsed = gasStart - gasleft();
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasUsed, true);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        emit GasReimbursed(gasUsed, reimbursementAmount, _target, REIMBURSEMENT_ADDRESS);
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
        uint256 gasUsed = gasStart - gasleft();
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasUsed, false);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        emit GasReimbursed(gasUsed, reimbursementAmount, _target, REIMBURSEMENT_ADDRESS);
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
        uint256 gasUsed = gasStart - gasleft();
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasUsed, true);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        emit GasReimbursed(gasUsed, reimbursementAmount, _target, REIMBURSEMENT_ADDRESS);
        return results;
    }

    function executeBatch(address _target, IBatchExecution.Call[] calldata _calls, bytes calldata _data)
        external
        onlyDelegated(_target)
        override
    {
        uint256 gasStart = gasleft();
        ITKGasDelegate(_target).executeBatch(_calls, _data);
        uint256 gasUsed = gasStart - gasleft();
        uint256 reimbursementAmount = _gasToReimburseInERC20(gasUsed, false);
        SafeTransferLib.safeTransferFrom(REIMBURSEMENT_ERC20, _target, REIMBURSEMENT_ADDRESS, reimbursementAmount);
        emit GasReimbursed(gasUsed, reimbursementAmount, _target, REIMBURSEMENT_ADDRESS);
    }
    */

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
