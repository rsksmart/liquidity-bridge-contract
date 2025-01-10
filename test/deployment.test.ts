import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";
import { deployLbcProxy } from "../scripts/deployment-utils/deploy-proxy";
import { upgradeLbcProxy } from "../scripts/deployment-utils/upgrade-proxy";
import { ZERO_ADDRESS } from "./utils/constants";
import { BRIDGE_ADDRESS } from "../scripts/deployment-utils/constants";

describe("LiquidityBridgeContract deployment process should", function () {
  let proxyAddress: string;

  it("should deploy LiquidityBridgeContract proxy and initialize it", async () => {
    const deployed = await deployLbcProxy(hre.network.name, { verbose: false });
    proxyAddress = deployed.address;
    const lbc = await ethers.getContractAt(
      "LiquidityBridgeContract",
      deployed.address
    );
    const result = await lbc.queryFilter(lbc.getEvent("Initialized"));
    expect(deployed.deployed).to.be.eq(true);
    expect(result.length).length.equal(1);
  });

  it("upgrade proxy to LiquidityBridgeContractV2", async () => {
    await upgradeLbcProxy(hre.network.name, { verbose: false });
    const lbc = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      proxyAddress
    );
    const version = await lbc.version();
    expect(version).to.equal("1.3.0");
  });

  it("validate minimiumCollateral arg in initialize", async () => {
    const LiquidityBridgeContract = await ethers.getContractFactory(
      "LiquidityBridgeContract",
      {
        libraries: {
          BtcUtils: ZERO_ADDRESS,
          SignatureValidator: ZERO_ADDRESS,
          Quotes: ZERO_ADDRESS,
        },
      }
    );
    const lbc = await LiquidityBridgeContract.deploy();
    const MINIMUM_COLLATERAL = ethers.parseEther("0.02");
    const RESIGN_DELAY_BLOCKS = 15;
    const initializeTx = lbc.initialize(
      BRIDGE_ADDRESS,
      MINIMUM_COLLATERAL,
      1,
      50,
      RESIGN_DELAY_BLOCKS,
      1,
      1,
      false
    );
    await expect(initializeTx).to.be.revertedWith("LBC072");
  });

  it("validate resignDelayBlocks arg in initialize", async () => {
    const LiquidityBridgeContract = await ethers.getContractFactory(
      "LiquidityBridgeContract",
      {
        libraries: {
          BtcUtils: ZERO_ADDRESS,
          SignatureValidator: ZERO_ADDRESS,
          Quotes: ZERO_ADDRESS,
        },
      }
    );
    const lbc = await LiquidityBridgeContract.deploy();
    const MINIMUM_COLLATERAL = ethers.parseEther("0.6");
    const RESIGN_DELAY_BLOCKS = 14;
    const initializeTx = lbc.initialize(
      BRIDGE_ADDRESS,
      MINIMUM_COLLATERAL,
      1,
      50,
      RESIGN_DELAY_BLOCKS,
      1,
      1,
      false
    );
    await expect(initializeTx).to.be.revertedWith("LBC073");
  });

  it("validate reward percentage arg in initialize", async () => {
    const LiquidityBridgeContract = await ethers.getContractFactory(
      "LiquidityBridgeContract",
      {
        libraries: {
          BtcUtils: ZERO_ADDRESS,
          SignatureValidator: ZERO_ADDRESS,
          Quotes: ZERO_ADDRESS,
        },
      }
    );
    const MINIMUM_COLLATERAL = ethers.parseEther("0.6");
    const RESIGN_DELAY_BLOCKS = 60;

    const parameters = {
      bridge: BRIDGE_ADDRESS,
      minCollateral: MINIMUM_COLLATERAL,
      minPegin: 1,
      resignBlocks: RESIGN_DELAY_BLOCKS,
      dustThreshold: 1,
      btcBlockTime: 1,
      mainnet: false,
    };
    const percentages = [
      { value: 0, ok: true },
      { value: 1, ok: true },
      { value: 99, ok: true },
      { value: 100, ok: true },
      { value: 101, ok: false },
    ];

    for (const { value, ok } of percentages) {
      const lbc = await LiquidityBridgeContract.deploy();
      const initializeTx = lbc.initialize(
        parameters.bridge,
        parameters.minCollateral,
        parameters.minPegin,
        value,
        parameters.resignBlocks,
        parameters.dustThreshold,
        parameters.btcBlockTime,
        parameters.mainnet
      );
      if (ok) {
        await expect(initializeTx).not.to.be.reverted;
        const reinitializeTx = lbc.initialize(
          parameters.bridge,
          parameters.minCollateral,
          parameters.minPegin,
          value,
          parameters.resignBlocks,
          parameters.dustThreshold,
          parameters.btcBlockTime,
          parameters.mainnet
        );
        // check that only initializes once
        await expect(reinitializeTx).to.be.reverted;
      } else {
        await expect(initializeTx).to.be.revertedWith("LBC004");
      }
    }
  });
});
