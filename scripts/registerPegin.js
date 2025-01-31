require('dotenv').config();
const mempoolJS = require("@mempool/mempool.js");
const pmtBuilder = require("@rsksmart/pmt-builder");
const bs58check = require('bs58check');
const bitcoin = require('bitcoinjs-lib');
const Web3 = require("web3");
const web3Provider = new Web3.providers.HttpProvider(
    config.config.network === 'rskMainnet' ? process.env.MAINNET_RPC_URL : process.env.TESTNET_RPC_URL
);
const web3 = new Web3(web3Provider);

// ------ REPLACE THE FOLLOWING DATA WITH THE DATA OF THE PEGIN YOU WANT TO REGISTER ------

const quoteJson = {
    "fedBTCAddr": "2MxdCCrmUaEG1Tk8dshdcTGKiA9LewNDVCb",
    "lbcAddr": "0x18d8212bc00106b93070123f325021c723d503a3",
    "lpRSKAddr": "0xdfcf32644e6cc5badd1188cddf66f66e21b24375",
    "btcRefundAddr": "mfWxJ45yp2SFn7UciZyNpvDKrzbhyfKrY8",
    "rskRefundAddr": "0x8dccd82443b80ddde3690af86746bfd9d766f8d2",
    "lpBTCAddr": "mwEceC31MwWmF6hc5SSQ8FmbgdsSoBSnbm",
    "callFee": "150000000000000",
    "penaltyFee": "10000000000000",
    "contractAddr": "0x8dccd82443b80ddde3690af86746bfd9d766f8d2",
    "data": "",
    "gasLimit": 21000,
    "nonce": "7021696521304749773",
    "value": "25000000000000000",
    "agreementTimestamp": "1730364504",
    "timeForDeposit": 7200,
    "lpCallTime": 9800,
    "confirmations": 2,
    "callOnRegister": false,
    "gasFee": "152375496000",
    "productFeeAmount": 0
};

const expectedHash = "c42182bd93537c91520572bbefc6b336f5ec75573e8876edd40430f1a025e0eb";

const signature = "9ef9209516b65a4a1105c2da42493588ae38c6fc5a7373f2db1eaf85d3d240031f61b98c6a87d6f7cad79153428c0470d53d69f2320f4e908538cc089d15c7441c";

const userTxId = "5f208a0c2520977379f1dd4710fae591a13896ee4b985c223a5cceecf7df40be";

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
        const registerPeginCaller = signer.address;
        console.log('Executing registerPegIn from ' + registerPeginCaller);

        const json = require("../build/contracts/LiquidityBridgeContractV2.json");
        const contract = new web3.eth.Contract(json.abi, networkInfo.lbcAddress);
        const quote = {
            fedBtcAddress: bs58check.decode(quoteJson.fedBTCAddr).slice(1),
            lbcAddress: quoteJson.lbcAddr,
            liquidityProviderRskAddress: quoteJson.lpRSKAddr,
            btcRefundAddress: bs58check.decode(quoteJson.btcRefundAddr),
            rskRefundAddress: quoteJson.rskRefundAddr,
            liquidityProviderBtcAddress: bs58check.decode(quoteJson.lpBTCAddr),
            callFee: quoteJson.callFee,
            penaltyFee: quoteJson.penaltyFee,
            contractAddress: quoteJson.contractAddr,
            data: '0x'+quoteJson.data,
            gasLimit: quoteJson.gasLimit,
            nonce: quoteJson.nonce,
            value: quoteJson.value,
            agreementTimestamp: quoteJson.agreementTimestamp,
            timeForDeposit: quoteJson.timeForDeposit,
            callTime: quoteJson.lpCallTime,
            depositConfirmations: quoteJson.confirmations,
            callOnRegister: quoteJson.callOnRegister,
            productFeeAmount: quoteJson.productFeeAmount,
            gasFee: quoteJson.gasFee
        };
        const quoteHash = await contract.methods.hashQuote(Object.values(quote))
            .call({ to: networkInfo.lbcAddress })
            .then(result => result.slice(2));
        if (quoteHash !== expectedHash) {
            throw new Error(`Invalid hash: ${quoteHash}`);
        }
        console.log("Quote hash is correct", quoteHash);

        const { bitcoin: { blocks, transactions } } = mempoolJS({
            hostname: 'mempool.space',
            network: config.config.network === 'rskMainnet' ? 'mainnet' : 'testnet'
        });

        const btcRawTxFull = await transactions.getTxHex({ txid: userTxId });
        const tx = bitcoin.Transaction.fromHex(btcRawTxFull);
        tx.ins.forEach((input) => { input.witness = []; });
        const btcRawTx = tx.toHex();
        const txStatus = await transactions.getTxStatus({ txid: userTxId });
        const blockTxids = await blocks.getBlockTxids({ hash: txStatus.block_hash });
        const pmt = pmtBuilder.buildPMT(blockTxids, userTxId);

        const gasEstimation = await contract.methods.registerPegIn(
            Object.values(quote),
            '0x' + signature,
            '0x' + btcRawTx,
            '0x' + pmt.hex,
            txStatus.block_height
        ).estimateGas();

        console.log("Gas estimation: ", gasEstimation);

        const registerPeginResult = await contract.methods.registerPegIn(
            Object.values(quote),
            '0x' + signature,
            '0x' + btcRawTx,
            '0x' + pmt.hex,
            txStatus.block_height
        ).call({ to: networkInfo.lbcAddress, from: registerPeginCaller, gasLimit: gasEstimation });

        console.log("Expected result: ", registerPeginResult);
        const receipt = await contract.methods.registerPegIn(
            Object.values(quote),
            '0x' + signature,
            '0x' + btcRawTx,
            '0x' + pmt.hex,
            txStatus.block_height
        ).send({ to: networkInfo.lbcAddress, from: registerPeginCaller, gasLimit: gasEstimation + 200 });
        console.log("Receipt: ");
        console.log(receipt);

    } catch (error) {
        console.error("Error running register pegin script: ");
        console.error(error);
    }
    callback();
};
