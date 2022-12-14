const Migrations = artifacts.require("Migrations");
const { deploy } =  require('../config');

module.exports = async function(deployer, network) {

  await deploy('Migrations', network, async (state) => {
    await deployer.deploy(Migrations);
    const response = await Migrations.deployed();
    state.address = response.address;
  });
};
