const json = require("../build/contracts/LiquidityBridgeContractV2.json");
const configJson = require("../config.json");

module.exports = async function (callback) {
    const network = config.network;
    let LBCAddress = '';

    if (network) {
        LBCAddress = configJson[network].LiquidityBridgeContract.address;
        console.log(LBCAddress);
        const contract = new web3.eth.Contract(
            json.abi,
            LBCAddress
        );

        const productFeePercentage = await contract.methods.productFeePercentage().call();
        const daoFeeCollectorAddress = await contract.methods.daoFeeCollectorAddress().call();

        console.log('DAO Fee Percentage: ', productFeePercentage);
        console.log('DAO Fee Collector Address ', daoFeeCollectorAddress);
    }

    //
    //
    // contract.methods
    //     .register(
    //         "First contract",
    //         "http://localhost/api",
    //         true,
    //         "both"
    //     )
    //     .call({
    //         // from: accounts[0],
    //         value: 1200000000000000000,
    //     })
    //     .then((response) => console.log("Success: " + response))
    //     .catch((err) => console.log("Error: " + err));
    //
    // // invoke callback
    callback();
};
