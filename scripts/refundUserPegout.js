require('dotenv').config();
const Web3 = require("web3");
const web3Provider = new Web3.providers.HttpProvider(
    config.config.network === 'rskMainnet' ? process.env.MAINNET_RPC_URL : process.env.TESTNET_RPC_URL
);
const web3 = new Web3(web3Provider);

// ------ REPLACE THE FOLLOWING DATA WITH THE DATA OF THE PEGOUT YOU WANT TO REFUND ------

const quoteHash = "2a64325b9f587fe206f46c92b2a12568815ad76427ad56e02e0946f08d12d7d2";

// ------ END OF THE DATA TO BE REPLACED ------

const networksInfo = {
    'rskDevelopment': {
        privateKeyEnv: 'DEV_SIGNER_PRIVATE_KEY',
        lbcAddress: '0x18D8212bC00106b93070123f325021C723D503a3',
    },
    'rskTestnet': {
        privateKeyEnv: 'TESTNET_SIGNER_PRIVATE_KEY',
        lbcAddress: '0xc2A630c053D12D63d32b025082f6Ba268db18300',
    },
    'rskMainnet': {
        privateKeyEnv: 'MAINNET_SIGNER_PRIVATE_KEY',
        lbcAddress: '0xAA9cAf1e3967600578727F975F283446A3Da6612',
    }
}

module.exports = async function (callback) {
    try {
        const networkInfo = networksInfo[config.config.network];
        web3.eth.accounts.wallet.add("0x"+process.env[networkInfo.privateKeyEnv]);
        const signer = web3.eth.accounts.wallet[0];
        const refundPegoutCaller = signer.address;
        console.log('Executing refundUserPegOut from ' + refundPegoutCaller);

        const json = require("../build/contracts/LiquidityBridgeContractV2.json");
        const contract = new web3.eth.Contract(json.abi, networkInfo.lbcAddress);


        const gasEstimation = await contract.methods.refundUserPegOut('0x' + quoteHash).estimateGas();

        console.log("Gas estimation: ", gasEstimation);

        const refundPegoutResult = await contract.methods.refundUserPegOut('0x' + quoteHash)
            .call({ to: networkInfo.lbcAddress, from: refundPegoutCaller, gasLimit: gasEstimation });

        console.log("Expected result: ", refundPegoutResult);
        const receipt = await contract.methods.refundUserPegOut('0x' + quoteHash)
            .send({ to: networkInfo.lbcAddress, from: refundPegoutCaller, gasLimit: gasEstimation + 200 });
        console.log("Receipt: ");
        console.log(receipt);

    } catch (error) {
        console.error("Error running refund pegout script: ");
        console.error(error);
    }
    callback();
};
