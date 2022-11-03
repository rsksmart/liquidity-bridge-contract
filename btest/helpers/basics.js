export async function estimateGas(deploy) {
    let gas = await deploy.estimateGas()
    gas = parseInt(gas)
    gas += parseInt(gas/4)

    return gas
}