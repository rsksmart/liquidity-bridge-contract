const LiquidityBridgeContractV1 = artifacts.require("LiquidityBridgeContractV1");

const quote = {
    fedBTCAddr: "2N3JQb9erL1SnAr3NTMrZiPQQ8dcjJp4idV",
    lbcAddr: "0xc2A630c053D12D63d32b025082f6Ba268db18300",
    lpRSKAddr: "0x7C4890A0f1D4bBf2C669Ac2d1efFa185c505359b",
    btcRefundAddr: "2N9sm43yNrTw7kcxFZEupXtYtgh7YTVQorK",
    rskRefundAddr: "0xB4BF5fbe395298CEcC00e4d4aDDC62B7192E6f9F",
    lpBTCAddr: "mhghaQCHedKZZQuFqSzg6Z3Rf1TqqDEPCc",
    callFee: 101368444000000,
    penaltyFee: 1000000,
    contractAddr: "0xB4BF5fbe395298CEcC00e4d4aDDC62B7192E6f9F",
    data: "",
    gasLimit: 21000,
    nonce: 2424835889795045890,
    value: 5000000000000000,
    agreementTimestamp: 1701165410,
    timeForDeposit: 3600,
    lpCallTime: 7200,
    confirmations: 2,
    callOnRegister: false,
    callCost: 1368444000000
}

module.exports = async function (callback) {
    let accounts = await web3.eth.getAccounts();

    const proxyAddress = "0x11D50Bcaff24425FC0b8E60a6818C5c455082bE7";

    const proxyInstance = await LiquidityBridgeContractV1.at(proxyAddress);

    console.log('Getting owner address');
    const ownerAddress = await proxyInstance.owner();
    console.log("Owner address: ", ownerAddress);

    console.log('Getting product fee percentage');
    const prodFee = await proxyInstance.productFeePercentage();
    console.log('Product fee percentage: ', prodFee.toString());

    console.log('Getting DAO fee collector address');
    const daoFeeCollectorAddr = await proxyInstance.daoFeeCollectorAddress();
    console.log('DAO fee collector Address: ', daoFeeCollectorAddr);

    // invoke callback
    callback();
};
