const { readFile } = require('fs').promises

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const formatHex = hexString => hexString.startsWith('0x') ? hexString : '0x' + hexString

async function sendFromAccount({ account, value, call, additionalGasLimit }) {
    const gasPrice = await web3.eth.getGasPrice().then(price => {
        return parseInt(price) + parseInt(web3.utils.toWei('1', 'gwei'))
    })
    const gasLimit = await call.estimateGas({ from: account.address, gasPrice })
        .then(gas => additionalGasLimit? gas + additionalGasLimit : gas)
    const tx = {
        from: account.address,
        gasPrice,
        gas: gasLimit,
        to: call._parent.options.address,
        value: value?.toString(),
        data: call.encodeABI()
    };
    const signedTx = await account.signTransaction(tx)
    return web3.eth.sendSignedTransaction(signedTx.rawTransaction)
}

function decodeLogs({ abi, receipt }) {
  const logs = receipt.logs;
  const parsedReceipt = {}

  for (const log of logs) {
      const event = abi.filter(e => e.type === "event" && e.signature === log.topics[0])[0]
      if (event) {
        const topics = event.anonymous? log.topics : log.topics.slice(1)
        const decodedLog = web3.eth.abi.decodeLog(event.inputs, log.data, topics)
        parsedReceipt[event.name] = decodedLog
      }
  }
  return parsedReceipt
}

function getBitcoinRpcCaller({ url, user, pass }, debug = false) {
    const headers = new Headers();
    headers.append("content-type", "application/json");
    const token = Buffer.from(`${user}:${pass}`).toString('base64')
    headers.append("Authorization", "Basic "+token);

    return async function (method, ...args) {
        const body = JSON.stringify({ 
            jsonrpc: "1.0",
            method: method.toLowerCase(),
            params: typeof args[0] === 'object' ? args[0] : args
        })
        const requestOptions = { method: 'POST', headers, body }
        if (debug) {
            console.log(body)
        }
        return fetch(url, requestOptions)
            .then(response => response.json())
            .then(response => {
                if (response.error) {
                    throw response.error
                }
                return response.result
            })
    }
}

async function loadConfig() {
    const buffer = await readFile('integration-test/test.config.json')
    return JSON.parse(buffer.toString())
}

module.exports = {
    sleep,
    formatHex,
    sendFromAccount,
    decodeLogs,
    getBitcoinRpcCaller,
    loadConfig
}