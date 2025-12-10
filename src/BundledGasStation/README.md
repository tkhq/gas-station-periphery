# Bundled Gas Station

The Bundled Gas Station allows executing multiple calls in a single transaction, with efficient transient storage caching for delegation checks.

## Features

- Batch execution of multiple calls
- Transient storage caching for delegation status
- Support for both direct calls and execute calls through TKGasDelegate
- Return data tracking with gas cost information

### Gas Savings

Bundled transactions in the Bundled Gas Station saves around 20k for EACH transaction bundle passed in since it is all done in one transaction. 



The overhead per bundled transaction is around 1000. The gas saved is the standard 21,000 gas for initiating the transaction.

The actual gas savings calulation is ```gasSaved = (21,000 - 1000 - (21,000/N))``` where N is number of bundled transactions. So bundling two transactions would save ~9.5k gas per bundled transaction. With 10 transactions it would save ~17.9k gas per bundled transaction.  

## Base Mainnet Deployment

- **TKBundledGasStation**: [0x90881B30d787c876d40679A821c83391144795B3](https://basescan.org/address/0x90881B30d787c876d40679A821c83391144795B3)

