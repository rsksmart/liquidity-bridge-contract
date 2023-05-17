async function estimateGas(deploy) {
    console.log('deploy estimategas: ', deploy.estimateGas)

    let gas = await deploy.estimateGas()
    console.log('gas: ', gas)
    gas = parseInt(gas)
    gas += parseInt(gas/4)

    return gas
}

module.exports = {
    estimateGas
}