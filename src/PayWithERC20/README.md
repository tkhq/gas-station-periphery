# Pay with ERC20 

_These contracts are still in beta and should be only used at your own risk. These are not eligible for bug bounty_ 

These contracts enable users to pay gas with an ERC-20 such as USDC

# Deployment

# Making a Custom Reimbursable Gas Station

# Threat Model

## What is it? 

This is a gas station built to interact with our gas delegate to enable end users to pay for gas with USDC in particular, but can be expanded to use any ERC-20

This prevents the user from griefing the paymaster by "pulling" an initial amount of USDC from the user, initiating the transaction, then returning the "change" back to the user. 

### Flow

This example uses USDC, but you could replace this with any ERC-20. This does not use transferFrom or any approve

1. User delegates to the gas delegate with a type 4 transaction. This can be paid for by the paymaster
2. The user signs two intents (gasless)
    a. The user signs an intent to allow the gas station to interact with USDC on behalf of the user up to a time limit (this can be cached safely)
    b. The user signs an intent for the actual execution they want to pay for in USDC
3. The paymaster then broadcasts the transaction with:
    a. The two signatures from step 2
    b. Calldata associated with that transaction
    c. The initial amount of USDC that will be used to pay for the transaction. This is called "_initialDepositERC20"
4. The gas station contract then:
    a. Pulls _initialDepositERC20 using a transfer and stores it in the contract using the session intent in step 2.a 
    b. Executes the transaction using the execution intent in step 2.b
    c. Calculates the cost of the transaction in USDC using an oracle, then adds a base fee and a percentage fee in basis points
    d. Based on the cost of the transaction:
        i. If it's less than _initialDepositERC20, it will pay the reimbursement address the cost plus fees, and give the user the change
        ii. If it's greater than _initialDepositERC20, it will pay reimbursement address the full _initialDepositERC20 amount and attempt to collect the remainder from the user

## What can go wrong? And what we are doing about it?

### User attempts to grief the paymaster by causing a catchable revert

Since the intents are gasless, the user can potenially get the paymaster to execute the transaction at no cost to the user.
The user can then have their execution revert midway, costing the paymaster up to the point of the revert, without paying the paymaster.  

#### Initial payment and swallowing reverts
We are first taking a small amount from the user, and then storing it in the gas station contract at the beginning of the transaction. 
If this fails, then it will revert quickly, preventing any more cost to the paymaster.
After execution, the gas station tries to account for the amount of gas used and then pay back the user and the paymaster.

The intial payment and validation will revert if:
1. The signature is an invalid length 
2. The target EoA is not delegated to our gas delegate
3. The initial ERC-20 deposit is too high (this protects the user rather than the paymaster)
4. The initial deposit reverts or does not fulfill the required amount
This ensures that this will not continue unless there is that initial deposit

From then on, the contract will NOT revert, and emit an event to notify an error if:
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
2. I amount is less than _transactionGasLimitWei, but more than the _initialDepositERC20, then the contract will attempt to reconcile this amount of money. There is no guarantee that this will be paid back, so the paymaster should set reasonable limits where the _initialDepositERC20 is more than the _transactionGasLimitWei when converted. Th

### The paymaster griefs the user with nonsensical transactions

### The paymaster steals funds from the user

### On failure to reimburse, funds are locked in the contract

### Oracle failure 

### Non-standard ERC-20s used as the reimbursement token

# Deployments

## Base Mainnet Deployments

- **ReimbursableGasStationUSDCFactory**: [0xE87DbF5f190b2aeAd45E64F73dbE7BeE25cAEcf1](https://basescan.org/address/0xE87DbF5f190b2aeAd45E64F73dbE7BeE25cAEcf1)
- **ReimbursableGasStationUSDC**: [0xd04fFb5927F94DfaBE82A8C43D88811EE6a8373e](https://basescan.org/address/0xd04fFb5927F94DfaBE82A8C43D88811EE6a8373e)