const fs = require('fs');
const testConfig = { test: {} };
exports.read = () => Object.keys(testConfig.test).length > 0 ? testConfig : JSON.parse(fs.readFileSync('config.json').toString());
exports.write = (newConfig) => {
    const oldConfig = this.read();
    fs.writeFileSync('config.json', JSON.stringify({ ...oldConfig, ...newConfig }, null, 2));
};




exports.deploy = async (name, network, act) => {
    const oldConfig = this.read();

    if (!oldConfig[network]) {
        oldConfig[network] = {};
    }

    if (!oldConfig[network][name]) {
        oldConfig[network][name] = {};
    }

    if (network === 'test') {
        testConfig.test[name] = {};
        await act(testConfig.test[name]);
        return testConfig;
    }

    if (!oldConfig[network][name].deployed || network === "rskRegtest") {
        await act(oldConfig[network][name]);
        oldConfig[network][name].deployed = true;
        this.write(oldConfig)
    } else {
        console.warn(`${name} has already be deployed [address: ${oldConfig[network][name].address}]. If you want to deploy it, please set deployed attribute to false on config.json file.`)
    }
    return this.read();
}



