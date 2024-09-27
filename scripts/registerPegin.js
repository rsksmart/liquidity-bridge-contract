require('dotenv').config();
const bs58check = require('bs58check');
const Web3 = require("web3");
const web3Provider = new Web3.providers.HttpProvider(process.env.MAINNET_RPC_URL);
const web3 = new Web3(web3Provider);

const LBC_ADDRESS = "0xAA9cAf1e3967600578727F975F283446A3Da6612";

// ------ REPLACE THE FOLLOWING DATA WITH THE DATA OF THE PEGIN YOU WANT TO REGISTER ------

const quoteJson = {
    "fedBTCAddr": "3LxPz39femVBL278mTiBvgzBNMVFqXssoH",
    "lbcAddr": "0xAA9cAf1e3967600578727F975F283446A3Da6612",
    "lpRSKAddr": "0x4202bac9919c3412fc7c8be4e678e26279386603",
    "btcRefundAddr": "171gGjg8NeLUonNSrFmgwkgT1jgqzXR6QX",
    "rskRefundAddr": "0xaD0DE1962ab903E06C725A1b343b7E8950a0Ff82",
    "lpBTCAddr": "17kksixYkbHeLy9okV16kr4eAxVhFkRhP",
    "callFee": "100000000000000",
    "penaltyFee": "10000000000000",
    "contractAddr": "0xaD0DE1962ab903E06C725A1b343b7E8950a0Ff82",
    "data": "",
    "gasLimit": 21000,
    "nonce": "8373381263192041574",
    "value": "8000000000000000",
    "agreementTimestamp": "1727298699",
    "timeForDeposit": 3600,
    "lpCallTime": 7200,
    "confirmations": 2,
    "callOnRegister": false,
    "gasFee": "1341211956000",
    "productFeeAmount": 0
};

const expectedHash = "9ef0d0c376a0611ee83a1d938f88cdc8694d9cb6e35780d253fb945e92647d68";

const signature = "8ccd018b5c1fb7eceba2a13f8c977ae362c0daccafa6d77a5eb740527dd177620bb6c2d072d68869b3a08b193b1356de564e73233ea1c2686078bf87e3c909a31c";

const btcRawTx = "010000000148e9e71dafee5a901be4eceb5aca361c083481b70496f4e3da71e5d969add1820000000017160014b88ef07cd7bcc022b6d73c4764ce5db0887d5b05ffffffff02965c0c000000000017a9141b67149e474f0d7757181f4db89257f27a64738387125b01000000000017a914785c3e807e54dc41251d6377da0673123fa87bc88700000000";

const pmt = "a71100000e7fe369f81a807a962c8e528debd0b46cbfa4f8dfbc02a62674dd41a73f4c4bde0508a9e309e5836703375a58ab116b95434552ca2e460c3273cd2caa13350aefc3c8152a8150f738cd18ff33e69f19b727bff9c2b92aa06e6d0971e9b49893075f2d926bbb9f0884640363b79b6a668a178f140c13f25b48ec975357822ce38c733f6de9b32f6910ff3cd838efd274cd784ab204b74f281ef68146c334f509613d022554f281465dfcd597305c988c4b06e297e5d777afdb66c3391c3c471ebf9a1e051ba38201f08ca758d2dc83a71c34088e6785c1a775e2bde492361462cac9e7042653341cd1e190d0265a33f46ba564dc6116689cf19a8af6816c006df69803008246d44bc849babfbcc3de601fba3d10d696bf4b4d9cb8e291584e7d24bb2c81282972e71cb4493fb4966fcb483d6b62b24a0e25f912ee857d8843e4fa6181b8351f0a300e14503d51f46f367ec872712004535a56f14c65430f044f9685137a1afb2dc0aa402fde8d83b072ef0c4357529466e017dfb2935444103bbeec61bf8944924371921eefd02f35fd5283f3b7bce58a6f4ca15fb32cee8869be8d7720501ec18cc097c236b19212514582212719aede2400b1dd1ff43208ac7504bfb60a00";

const height = 862859;

// ------ END OF THE DATA TO BE REPLACED ------

module.exports = async function (callback) {
    try {
        web3.eth.accounts.wallet.add("0x"+process.env.MAINNET_SIGNER_PRIVATE_KEY);
        const signer = web3.eth.accounts.wallet[0];
        const registerPeginCaller = signer.address;
        console.log('Executing registerPegIn from ' + registerPeginCaller);

        const json = require("../build/contracts/LiquidityBridgeContractV2.json");
        const contract = new web3.eth.Contract(json.abi, LBC_ADDRESS);
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
            data: '0x',
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
            .call({ to: LBC_ADDRESS })
            .then(result => result.slice(2));
        if (quoteHash !== expectedHash) {
            throw new Error(`Invalid hash: ${quoteHash}`);
        }
        console.log("Quote hash is correct", quoteHash);

        const gasEstimation = await contract.methods.registerPegIn(
            Object.values(quote),
            '0x' + signature,
            '0x' + btcRawTx,
            '0x' + pmt,
            height
        ).estimateGas();

        console.log("Gas estimation: ", gasEstimation);

        const registerPeginResult = await contract.methods.registerPegIn(
            Object.values(quote),
            '0x' + signature,
            '0x' + btcRawTx,
            '0x' + pmt,
            height
        ).call({ to: LBC_ADDRESS, from: registerPeginCaller, gasLimit: gasEstimation });

        console.log("Expected result: ", registerPeginResult);
        const receipt = await contract.methods.registerPegIn(
            Object.values(quote),
            '0x' + signature,
            '0x' + btcRawTx,
            '0x' + pmt,
            height
        ).send({ to: LBC_ADDRESS, from: registerPeginCaller, gasLimit: gasEstimation + 200 });
        console.log("Receipt: ");
        console.log(receipt);

    } catch (error) {
        console.error("Error running register pegin script: ");
        console.error(error);
    }
    callback();
};
