// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ReimbursableGasStationUSDC} from "../src/USDC/ReimbursableGasStationUSDC.sol";
import {MockOracle} from "./mocks/MockOracle.t.sol";
import {MockERC20} from "./mocks/MockERC20.t.sol";
import {TKGasDelegate} from "../lib/gas-station/src/TKGasStation/TKGasDelegate.sol";
import {ITKGasDelegate} from "../lib/gas-station/src/TKGasStation/interfaces/ITKGasDelegate.sol";

contract ReimbursableGasStationUSDCTestBase is Test {
    ReimbursableGasStationUSDC public gasStation;
    MockOracle public mockOracle;
    MockERC20 public usdcToken;
    MockERC20 public someToken;
    TKGasDelegate public tkGasDelegate;

    address public reimbursementAddress;
    address public paymaster;
    address payable public userA;

    uint16 public constant GAS_FEE_BASIS_POINTS = 100; // 1% (100 basis points)
    uint256 public constant BASE_GAS_FEE = 21000; // Base gas fee
    uint256 public constant MAX_GAS_LIMIT = 10_000_000_000; // Max gas limit in ERC20 tokens
    uint8 public constant ORACLE_DECIMALS = 8;

    uint256 public constant USERA_PRIVATE_KEY = 0xAAAAAA;

    function setUp() public virtual {
        // Deploy mock oracle
        mockOracle = new MockOracle(ORACLE_DECIMALS);

        // Set initial price data (e.g., ETH/USD price of $1 with 8 decimals - very cheap for testing)
        mockOracle.setLatestRoundData(
            1, // roundId
            1e8, // answer: $1 with 8 decimals (much cheaper for testing)
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        // Deploy mock ERC20 token for reimbursement
        usdcToken = new MockERC20("USD Coin", "USDC");

        // Deploy mock ERC20 token for some token
        someToken = new MockERC20("Some Token", "SOME");

        // Deploy TKGasDelegate
        tkGasDelegate = new TKGasDelegate();

        // Set up addresses
        reimbursementAddress = makeAddr("reimbursementAddress");
        paymaster = makeAddr("paymaster");
        userA = payable(vm.addr(USERA_PRIVATE_KEY));

        // Deploy ReimbursableGasStationUSDC
        gasStation = new ReimbursableGasStationUSDC(
            address(mockOracle),
            address(tkGasDelegate),
            reimbursementAddress,
            address(usdcToken),
            GAS_FEE_BASIS_POINTS,
            BASE_GAS_FEE,
            MAX_GAS_LIMIT
        );

        // Delegate userA to the gas delegate
        _delegate(USERA_PRIVATE_KEY, paymaster);
    }

    function _delegate(uint256 _userPrivateKey, address _paymaster) internal {
        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(payable(address(tkGasDelegate)), _userPrivateKey);

        vm.prank(_paymaster);
        vm.attachDelegation(signedDelegation);
        vm.stopPrank();
    }

    function _signSessionExecuteWithSender(
        uint256 _privateKey,
        address payable _publicKey,
        uint128 _counter,
        uint32 _deadline,
        address _sender,
        address _outputContract
    ) internal returns (bytes memory) {
        address signer = vm.addr(_privateKey);
        vm.startPrank(signer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _privateKey,
            TKGasDelegate(_publicKey).hashSessionExecution(_counter, uint32(_deadline), _sender, _outputContract)
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        return signature;
    }

    function _constructPackedSessionSignatureData(bytes memory _signature, uint128 _counter, uint32 _deadline)
        internal
        pure
        returns (bytes memory)
    {
        // Packed format: signature (65 bytes) + counter (16 bytes) + deadline (4 bytes) = 85 bytes
        bytes memory counterBytes = abi.encodePacked(_counter);
        // Ensure counter is exactly 16 bytes (uint128)
        require(counterBytes.length <= 16, "Counter too large");
        if (counterBytes.length < 16) {
            // Right-align the counter by padding with zeros on the left
            bytes memory padding = new bytes(16 - counterBytes.length);
            counterBytes = abi.encodePacked(padding, counterBytes);
        }
        return abi.encodePacked(_signature, counterBytes, _deadline);
    }

    function _constructExecuteBytes(
        bytes memory _signature,
        uint128 _nonce,
        uint32 _deadline,
        address _to,
        uint256 _value,
        bytes memory _args
    ) internal pure returns (bytes memory) {
        require(_signature.length == 65, "sig len");
        bytes16 nonce16 = bytes16(uint128(_nonce));
        // For executeReturns(address _to, uint256 _value, bytes calldata _data),
        // _data should only contain: signature(65) + nonce(16) + deadline(4) + args
        // _to and _value are passed as separate parameters
        return abi.encodePacked(_signature, nonce16, bytes4(_deadline), _args);
    }

    function _signExecute(
        uint256 _privateKey,
        address payable _publicKey,
        uint128 _nonce,
        uint32 _deadline,
        address _outputContract,
        uint256 _ethAmount,
        bytes memory _arguments
    ) internal returns (bytes memory) {
        address signer = vm.addr(_privateKey);
        vm.startPrank(signer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _privateKey,
            TKGasDelegate(_publicKey).hashExecution(_nonce, _deadline, _outputContract, _ethAmount, _arguments)
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        return signature;
    }

    function test_CreateSessionPackedData() public {
        // Set a very low gas price for testing (1 gwei = 1e9 wei)
        vm.txGasPrice(1e9);

        uint128 counter = 1;
        uint32 deadline = uint32(block.timestamp + 1 hours);
        someToken.mint(userA, 100);
        uint256 userAStartBalance = 5000 * 10 ** 6;
        usdcToken.mint(userA, userAStartBalance); // money to pay the gas

        address receiver = makeAddr("receiver");

        uint256 reimbursementStartBalance = usdcToken.balanceOf(reimbursementAddress);

        // Create signature for session execution
        bytes memory signature = _signSessionExecuteWithSender(
            USERA_PRIVATE_KEY,
            userA,
            counter,
            deadline,
            address(gasStation), // sender is the gas station
            address(usdcToken) // output contract is USDC
        );

        // Construct packed session signature data (85 bytes)
        bytes memory packedSessionData = _constructPackedSessionSignatureData(signature, counter, deadline);

        // Verify the packed data is exactly 85 bytes
        assertEq(packedSessionData.length, 85, "Packed session data should be 85 bytes");

        uint128 nonce = ITKGasDelegate(userA).nonce();
        bytes memory args = abi.encodeWithSelector(someToken.transfer.selector, receiver, 10);
        bytes memory executeSignature =
            _signExecute(USERA_PRIVATE_KEY, userA, nonce, uint32(block.timestamp + 86400), address(someToken), 0, args);
        bytes memory executeData = _constructExecuteBytes(
            executeSignature, nonce, uint32(block.timestamp + 86400), address(someToken), 0, args
        );
        // Calculate gas limit in ERC20 tokens (using a reasonable estimate)
        // For testing, we'll use a fixed amount - in production this would be calculated based on gas price
        // With gas price = 1 gwei and ETH price = $1, even 1M gas would be:
        // 1000000 * 1e9 * 1e8 * 1e6 / 1e26 = 1e27 / 1e26 = 10 USDC (6 decimals) = 10000000
        // But we need a large buffer for actual gas usage, fees, and base gas fee
        uint256 gasLimitERC20 = 1_000_000_000; // 1000 USDC (6 decimals) - large buffer for the test
        gasStation.executeReturns(gasLimitERC20, userA, address(someToken), 0, packedSessionData, executeData);

        assertEq(someToken.balanceOf(receiver), 10);
        assertGt(usdcToken.balanceOf(reimbursementAddress), reimbursementStartBalance);
        assertEq(someToken.balanceOf(userA), 90);
        assertLt(usdcToken.balanceOf(userA), userAStartBalance);
        assertEq(usdcToken.balanceOf(address(gasStation)), 0);
    }
}
