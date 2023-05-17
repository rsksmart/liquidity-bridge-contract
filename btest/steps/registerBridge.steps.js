const assert = require('assert').strict;
const { Given, When, Then } = require('@cucumber/cucumber');
const { abi, bytecode } = require('../../build/contracts/LiquidityBridgeContract.json')
const ganache = require('ganache-cli'); // Mockup of eth network
const web3 = new (require('web3'))(ganache.provider());
const { estimateGas } = require('../helpers/basics');

// const state = {
//     error: undefined,
// }

// todo: check if are real vals
const bridgeAddress = '0x0000000000000000000000000000000001000006';
const MINIMUM_COLLATERAL = "1"; // amount in wei
const MINIMUM_PEG_IN = "500000000000000000"; // amount in wei
const REWARD_PERCENTAGE = 10;
const RESIGN_DELAY_BLOCKS = 1;
const DUST_THRESHOLD = 2300 * 65164000;

let instance;

When (/User register as LP for the first time$/, async function () {
    const accounts = await web3.eth.getAccounts()

    try {
        instance = new web3.eth.Contract(abi)
            .deploy({
                data: bytecode,
                arguments: [bridgeAddress, MINIMUM_COLLATERAL, MINIMUM_PEG_IN, REWARD_PERCENTAGE, RESIGN_DELAY_BLOCKS, DUST_THRESHOLD]
            })
        console.log('deploy: ', instance)

        // const gas = await estimateGas(deploy)
        const gas = 5000000

        console.log('gas', gas)
        console.log('accounts[0]', accounts[0])
        // instance = await deploy.send({
        //     from: accounts[0],
        //     gas
        // })

        // {from: currAddr, value : utils.LP_COLLATERAL}
        // console.log('instance methods: ', instance._parent.methods)
        const registerMethod = instance._parent.methods.register();
        console.log('register method', registerMethod)
        const methodGas = await estimateGas(registerMethod);
        console.log('register method gas', methodGas)

        const tx = await registerMethod.send({from: accounts[1], value: web3.utils.toBN(100)})
        console.log('transaction: ', tx)
    } catch (e) {
        console.error("err: ", e)
    }
})


Then (/User is registered as LP$/, async function () {
    console.log('then: ', 1)
})