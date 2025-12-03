# Pay with ERC20 

_These contracts are still in beta and should be only used at your own risk. These are not eligible for bug bounty_ 

These contracts enable users to pay gas with an ERC-20 such as USDC

# Deployment

To deploy, clone, and run:
```bash
forge install
```

Then for your network, set the right configuration in `foundry.toml` to have the RPC URL for the network, and where to validate 

```toml
[rpc_endpoints]
NETWORK = "${NETWORK_RPC_URL}"     # e.g. https://base-mainnet.g.alchemy.com/v2/YOUR_API_KEY

[etherscan]
NETWORK = { key = "${ETHERSCAN_API_KEY}", url = "https://api.basescan.org/api" }
```

Then for the factory and gas station, copy `script/PayWithERC20/env.example` into a new `.env` file and set:

```env
PRIVATE_KEY=0x...
REIMBURSEMENT_ADDRESS=0x...

# Oracle & token config
PRICE_FEED=0x...
REIMBURSEMENT_ERC20=0x...
TK_GAS_DELEGATE=0x000066a00056CD44008768E2aF00696e19A30084

# Gas station economics
GAS_FEE_BASIS_POINTS=100
BASE_GAS_FEE_WEI=60000
BASE_GAS_FEE_ERC20=1000
MAX_DEPOSIT_LIMIT_ERC20=10000000
MINIMUM_TRANSACTION_GAS_LIMIT_WEI=60000

# CREATE2 salt for factory-created gas station
GAS_STATION_SALT=0x...
```

In the future, for making a new gas station with a new fee tier or place to reimburse to, you simply need to call that factory unless you need to change out the oracle. 

 Run the command to deploy:

```bash
forge script script/PayWithERC20/DeployReimbursableGasStationUSDCAndFactory.s.sol \
  --rpc-url NETWORK \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Finally, open a PR to add the deploy to this readme. 

# Making a Custom Reimbursable Gas Station

If you want to make a custom gas station that uses Chainlink's AggregatorV3Interface with different ERC-20, you can inherit from ReimbursableGasStationAggregatorV3Oracle or deploy an instance of it with the right arguments. 

If you want to make a custom gas station to use a different ERC-20 and not use the AggregatorV3Interface, you can inherit from AbstractReimbursableGasStation and implement the _convertGasToERC20 function to use a custom oracle
```solidity
function _convertGasToERC20(uint256 _gasAmount) internal virtual returns (uint256);
```

# Fee calculation

The fees are calculated in _calculateReimbursementAmount

```solidity
    function _calculateReimbursementAmount(uint256 _gasStart) internal returns (uint256, uint256) {
        uint256 gasUsed = _gasStart - gasleft();
        gasUsed += (gasUsed * GAS_FEE_BASIS_POINTS / 10000) + BASE_GAS_FEE_WEI;

        return (gasUsed, _convertGasToERC20(gasUsed) + BASE_GAS_FEE_ERC20);
    }
```

The _gasStart variable tries to come from *as early as possible* in the transaction, not just wrapping the customer's desired execution. 
The purpose of BASE_GAS_FEE_WEI is to cover the cost of all the transfers needed to account during this transaction. On L2s, I suggest you set this to at least 60,000 wei.
The purpose of BASE_GAS_FEE_ERC20 is to prevent sybil attacks and to have an absolute minimum amount of profit per transaction. I suggest setting this to a very small number. I use 1/10 of a cent in testing.
The purpose of GAS_FEE_BASIS_POINTS is to calculate the profit per transaction. This does not get multiplied against the BASE_GAS_FEE_WEI


# Threat Model

## What is it? 

This is a gas station built to interact with our gas delegate to enable end users to pay for gas with USDC in particular, but can be expanded to use any ERC-20

This prevents the user from griefing the paymaster by "pulling" an initial amount of USDC from the user, initiating the transaction, then returning the "change" back to the user. 

### Flow

This example uses USDC, but you could replace this with any ERC-20. This does not use transferFrom or any approve

1. User delegates to the gas delegate with a type 4 transaction. This can be paid for by the paymaster.
2. The user signs two intents (gasless):
   - The user signs an intent to allow the gas station to interact with USDC on behalf of the user up to a time limit (this can be cached safely).
   - The user signs an intent for the actual execution they want to pay for in USDC.
3. The paymaster then broadcasts the transaction with:
   - The two signatures from step 2.
   - Calldata associated with that transaction.
   - The initial amount of USDC that will be used to pay for the transaction. This is called `_initialDepositERC20`.
4. The gas station contract then:
   - Pulls `_initialDepositERC20` using a transfer and stores it in the contract using the session intent in step 2.a.
   - Executes the transaction using the execution intent in step 2.b.
   - Calculates the cost of the transaction in USDC using an oracle, then adds a base fee and a percentage fee in basis points.
   - Based on the cost of the transaction:
     - If it's less than `_initialDepositERC20`, it will pay the reimbursement address the cost plus fees, and give the user the change.
     - If it's greater than `_initialDepositERC20`, it will pay reimbursement address the full `_initialDepositERC20` amount and attempt to collect the remainder from the user.

## What can go wrong? And what we are doing about it?

### User attempts to grief the paymaster by causing a catchable revert

Since the intents are gasless, the user can potenially get the paymaster to execute the transaction at no cost to the user.
The user can then have their execution revert midway, costing the paymaster up to the point of the revert, without paying the paymaster.  

#### Initial payment and swallowing reverts
We are first taking a small amount from the user, and then storing it in the gas station contract at the beginning of the transaction. 
If this fails, then it will revert quickly, preventing any more cost to the paymaster.
After execution, the gas station tries to account for the amount of gas used and then pay back the user and the paymaster.

The intial payment and validation will revert (fail-fast) if:
1. The signature is an invalid length 
2. The target EoA is not delegated to our gas delegate
3. The initial ERC-20 deposit is too high (this protects the user rather than the paymaster)
4. The initial deposit reverts or does not fulfill the required amount
This ensures that this will not continue unless there is that initial deposit

From then on, the contract will try to NOT revert, and emit an event to notify an error if:
1. There is a revert in the with execution; meaning that the user's transaction failed
2. There are failures in sending funds to repay the user or pay the recipient 
This is so there is a _guarantee_ that the recipient address will get paid even if there is a revert in an external contract. The user cannot have interactions happen without that deposit and paying that minimum.

#### Validating that the user has been delegated properly
Using _isDelegated, during run time, the user is checked to make sure they are delegated to our expected delegate contract, so session calls and execute calls will work as planned. 

#### User tries to grief the paymaster by causing an uncatchable revert (out of gas error)

If there is an out of gas error, the whole transaction will revert
This means the paymaster will pay gas, but not get any ERC-20 in return
In the call to execute in the delegate, we can set a gas limit to catch that revert as _transactionGasLimitWei
The transferfunctions for the ERC-20 do NOT have this parameter, so the paymaster should budget that in otherwise they will not get paid

### User's transactions are more expensive than anticipated

If the user's transaction is more expensive than anticipated then either:
1. The contract catches the revert when the gas is greater than _transactionGasLimitWei, and then continues as normal
2. I amount is less than _transactionGasLimitWei, but more than the _initialDepositERC20, then the contract will attempt to reconcile this amount of money. There is no guarantee that this will be paid back, so the paymaster should set reasonable limits where the _initialDepositERC20 is more than the _transactionGasLimitWei when converted. If this is in a failure state, it will not revert, but instead emit a GasUnpaid event. 

### The paymaster griefs the user with nonsensical transactions

The paymaster is given a session intent that allows the gas station to do unlimited transactions with the ERC-20 on behalf of the user. The gas station will only perform that transfer if the session is valid and the budgeted _transactionGasLimitWei is greater than the minimum.

A malicious paymaster could attempt an attack like:
1. Get a valid session intent from the user (replayable by design)
2. Send in a transaction that will definitely fail on execution
3. Collect the gas cost of that transaction + the base fee

This works as long as the session intent is valid. 
To mitigate this, the user should set a short time to live on that intention (only a few blocks), and if the paymaster is malicious, the user should burn the counter associated with that sesssion.
An untrustworthy paymaster should simply not be used if this is going on

An alternative solution is to:
1. Store the session as a limited number of times to be used in the contract to a constant maximum. This is acceptable, but not ideal since this would add an extra mapping to store each session and number of times it was used. This extra mapping would require another storage read and write on each transaction. 
2. Have the user give another signature to limit on run time. This is unacceptable since it would add another signature required for the user, and we're already needing 2 signatures

### The paymaster steals funds from the user

By design gas station can move the ERC-20 as the user.
This is limited by the fact the gas station has clear rules on how it will move as the user. Initially, it only takes the deposit, and can only take more if the gas cost was calculated to be more than the deposit but less than the budgeted amount. 

These contracts are immutable so the paymaster cannot change the rules on how the user's money is transferred. 

### On failure to reimburse, funds are locked in the contract

It is unlikely, but possible, that the contract is unable to transfer reimbursements or change to the right place and there is a failure on transfer. At this point, the contract will emit a TransferFailedUnclaimedStored even, and intended recipient can claim it with claimUnclaimedGasReimbursements.  

### Non-standard ERC-20s used as the reimbursement token

_For USDC, the ERC20_TRANSFER_SUCCEEDED_RETURN_DATA_CHECK immutable should always be set to FALSE in the constructor since it is standard_

In the constructor, there is a ERC20_TRANSFER_SUCCEEDED_RETURN_DATA_CHECK immutable that can be set to true if the ERC-20 being used does NOT revert on transfer when the transfer fails, and then returns a boolean FALSE instead. This is to handle non-standard ERC-20 implementations.
Without this extra check, if the paymaster is using non-standard ERC-20s for reimbursements, this could fail open, and the contract will believe that all be reimbursed.

### Oracle failure 

If the oracle becomes untrustworthy or fails for some reason, then the contract cannot calculate the price of gas. At this point, the contract should be abandonded and be redeployed with a new oracle.

Using a USD (not USDC) oracle is acceptable for testing if a network doesn't have a USDC oracle, but due to depeg risk, it's better to use a proper gasToken/USDC oracle.

For USDC on Base, we intend to use the ETH/USDC Chainlink oracle, which is large enough that if it were to fail, there would be larger problems in the industry than just this contract. 

# Logging risky events and what to do in case of disaster

1. A large number of reverts during the validation steps; any error in https://github.com/tkhq/gas-station-periphery/blob/main/src/PayWithERC20/AbstractReimbursableGasStation.sol#L11-L15 would cost the paymaster gas. Example https://github.com/tkhq/gas-station-periphery/blob/main/src/PayWithERC20/AbstractReimbursableGasStation.sol#L210. These are situations where the attacker gains nothing, but we are paying for it since the transaction can't start. Addresses that ask for this a lot should be banned/rate limited. This is meant to "fail fast" in case the user doesn't have enough funds or the target is not delegated properly

2. TransferFailedUnclaimedStored event where the paymaster can't get the payment from the transaction, but the funds are safely stored in the contract https://github.com/tkhq/gas-station-periphery/blob/main/src/PayWithERC20/AbstractReimbursableGasStation.sol#L239 and https://github.com/tkhq/gas-station-periphery/blob/main/src/PayWithERC20/AbstractReimbursableGasStation.sol#L260. In this case, it's wise to look up why it could not pay back the transaction. If something is wrong with the reciever, or the ERC-20 we're using is broken then it's best to abandon this contract instance and use the factory to create a new one.

3. GasUnpaid event where the paymaster was not paid back https://github.com/tkhq/gas-station-periphery/blob/main/src/PayWithERC20/AbstractReimbursableGasStation.sol#L251. This is the most dangerous where the calculation was not able to get paid back. The end user created a very expensive transaction, and the initial deposit was unable to cover it, and the end user had no funds to pay this back. This can happen by accident occasionally, but if it happens a lot, that user is most likely doing something malicious.


# Deployments

## Base Mainnet Deployments

- **ReimbursableGasStationUSDCFactory**: [0x6e2c08084FBa286Ed2113aE70e84252b4Ed1576A](https://basescan.org/address/0x6e2c08084FBa286Ed2113aE70e84252b4Ed1576A)
- **ReimbursableGasStationUSDC**: [0x1966ad010A705ED1d1a4Ea8b0933De1888aB1e97](https://basescan.org/address/0x1966ad010A705ED1d1a4Ea8b0933De1888aB1e97#code)

## Monad Mainnet Deployments

- **ReimbursableGasStationUSDCFactory**: [0x5ce1877F39722A207E014bb172d3edC8f080dC84](https://monadscan.com/address/0x5ce1877F39722A207E014bb172d3edC8f080dC84)
- **ReimbursableGasStationUSDC**: [0x339E29a155F180dc0f41B091F3Eb403Fa83a4882](https://monadscan.com/address/0x339E29a155F180dc0f41B091F3Eb403Fa83a4882)