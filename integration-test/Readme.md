# Integration test
The purpose of this test is to validate that the basic flow of the pegin and pegout works in a particular network

## Configuration
To run the test you need to have a file named `test.config.json` with the same format as `test.config.example.json`. The fields are the following:
- **pollingIntervalInSeconds**: number of seconds that the test is going to wait to check again during long lasting operations. E. g. waiting for bitcoin transaction confirmations
- **lbcAddress**: the address of the `LiquidityBridgeContract` in the network where the test is running
- **btcUtilsAddress**: the address of the `BtcUtils` library in the network where the test is running
- **lpPrivateKey**: the PK of the account that is going to act as liquidity provider during the test. This address must be registered as LP on the contract before running the test
- **lpBtcAddress**: bitcoin address of the wallet that is going to act as liquidity providers's wallet during test
- **userPrivateKey**: the PK of the account that is going to act as user during the test
- **userBtcAddress**: bitcoin address of the wallet that is going to act as user's wallet during test
- **btc**: url, user and password of the bitcoin rpc server that is going to be used to perform the bitcoin transactions

## How to run
1. Register the liquidity provider address in the `LiquidityBridgeContract`
2. Complete the config file fields
3. Add the network to `truffe-config.js` file
4. Run `npm run test:integration <network>`

## Constraints
- The LP address that is set on config file must be registered as LP in the contract
- The ABI files in `build` folder need to correspond with the contract that is being tested
- Timeout must be disabled