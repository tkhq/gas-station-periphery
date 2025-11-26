# Pay with ERC20 

_These contracts are still in beta and should be only used at your own risk. These are not eligible for bug bounty_ 

These contracts enable users to pay gas with an ERC-20 such as USDC

# Deployments

## Base Mainnet Deployments

- **ReimbursableGasStationUSDCFactory**: [0xE87DbF5f190b2aeAd45E64F73dbE7BeE25cAEcf1](https://basescan.org/address/0xE87DbF5f190b2aeAd45E64F73dbE7BeE25cAEcf1)
- **ReimbursableGasStationUSDC**: [0xd04fFb5927F94DfaBE82A8C43D88811EE6a8373e](https://basescan.org/address/0xd04fFb5927F94DfaBE82A8C43D88811EE6a8373e)


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
    c. The initial amount of USDC that will be used to pay for the transaction. This is called "_gasLimitERC20"
4. The gas station contract then:
    a. Pulls _gasLimitERC20 using a transfer and stores it in the contract using the session intent in step 2.a 
    b. Executes the transaction using the execution intent in step 2.b
    c. Calculates the cost of the transaction in USDC using an oracle, then adds a base fee and a percentage fee in basis points
    d. Based on the cost of the transaction:
        i. If it's less than _gasLimitERC20, it will pay the reimbursement address the cost plus fees, and give the user the change
        ii. If it's greater than _gasLimitERC20, it will pay reimbursement address the full _gasLimitERC20 amount and attempt to collect the remainder from the user

## What can go wrong? And what we are doing about it?

### User attempts to grief the paymaster

Since the intents are gasless, the user can potenially get the paymaster to execute the transaction at no cost to the user.
The user can then have their execution revert midway, costing the paymaster up to the point of the revert, without paying the paymaster.  

#### What we are doing about it? 

### User's transactions are more expensive than anticipated

#### What we are doing about it? 

### The paymaster steals funds from the user

#### What we are doing about it? 

### On failure to reimburse, funds are locked in the contract

#### What we are doing about it? 