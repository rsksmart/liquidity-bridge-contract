import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";
import { deployLbcProxy } from "../scripts/deployment-utils/deploy-proxy";
import { upgradeLbcProxy } from "../scripts/deployment-utils/upgrade-proxy";

describe("LiquidityBridgeContract deployment process should", function () {
    let proxyAddress:string;
    it("should deploy LiquidityBridgeContract proxy and initialize it", async () => {
        const deployed = await deployLbcProxy(hre.network.name, { verbose: false });
        proxyAddress = deployed.address;
        const lbc = await ethers.getContractAt('LiquidityBridgeContract', deployed.address);
        const result = await lbc.queryFilter(lbc.getEvent('Initialized'));
        expect(deployed.deployed).to.be.eq(true);
        expect(result.length).length.equal(1);
    });
    it("upgrade proxy to LiquidityBridgeContractV2", async () => {
        await upgradeLbcProxy(hre.network.name, { verbose: false });
        const lbc = await ethers.getContractAt('LiquidityBridgeContractV2', proxyAddress);
        const version = await lbc.version();
        expect(version).to.equal('1.3.0');
    });
});
