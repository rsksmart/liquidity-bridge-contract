const json = require("../build/contracts/LiquidityBridgeContractV2.json");
const configJson = require("../config.json");

function getTestPegOutQuote(lbcAddress, lpRskAddress, rskRefundAddress, value) {
    let valueToTransfer = value || web3.utils.toBN(0);
    let callFee = web3.utils.toBN(1);
    let nonce = 0;
    let agreementTimestamp = 1661788988;
    let expireDate = Math.round(new Date().getTime() / 1000) + 3600;
    let expireBlock = 4000;
    let transferTime = 1661788988;
    let depositDateLimit = Math.round(new Date().getTime() / 1000) + 600;
    let depositConfirmations = 10;
    let transferConfirmations = 10;
    let penaltyFee = web3.utils.toBN(0);
    let productFeeAmount = web3.utils.toBN(1);
    const gasFee = web3.utils.toBN(1);

    let quote = {
        lbcAddress,
        lpRskAddress,
        btcRefundAddress: "0x000000000000000000000000000000000000000000",
        rskRefundAddress,
        lpBtcAddress: "0x000000000000000000000000000000000000000000",
        callFee,
        penaltyFee,
        nonce,
        deposityAddress: "0x6f3c5f66fe733e0ad361805b3053f23212e5755c8d",
        value: valueToTransfer,
        agreementTimestamp,
        depositDateLimit,
        depositConfirmations,
        transferConfirmations,
        transferTime,
        expireDate,
        expireBlock,
        productFeeAmount,
        gasFee
    };

    return quote;
}

function asArray(obj) {
    return Object.values(obj);
}

module.exports = async function (callback) {
    let LBCAddress = '0xAA9cAf1e3967600578727F975F283446A3Da6612';

    const contract = new web3.eth.Contract(
        json.abi,
        LBCAddress
    );
    const quote = getTestPegOutQuote(
        LBCAddress,
        "0x4202bAC9919C3412Fc7c8BE4e678e26279386603",
        "0x79568c2989232dCa1840087D73d403602364c0D4",
        5000000000000000);

    console.log("Quote to be hashed: ", quote);

    try {
        const productFeePercentage = await contract.methods.productFeePercentage().call();
        const daoFeeCollectorAddress = await contract.methods.daoFeeCollectorAddress().call();
        const quoteHash = await contract.methods.hashPegoutQuote(asArray(quote)).call();
        const provider = await contract.methods.getProviders([1]).call();

        console.log("Proxy address: ", LBCAddress);
        console.log('DAO Fee Percentage: ', productFeePercentage);
        console.log('DAO Fee Collector Address ', daoFeeCollectorAddress);
        console.log('Provider ', provider)
        console.log('Quote Hash: ', quoteHash);
    } catch (error) {
        console.error(error);
    }

    callback();
};
