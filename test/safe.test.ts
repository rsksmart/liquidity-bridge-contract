import hre, { ethers } from "hardhat";
import { expect } from "chai";
import { GnosisSafe, GnosisSafeProxyFactory } from "../typechain-types";
import { ContractTransactionResponse } from "ethers";
import { deployLbcProxy } from "../scripts/deployment-utils/deploy-proxy";
import { getContractAt } from "@nomicfoundation/hardhat-ethers/internal/helpers";

const TransparentProxyABI = [
  "function admin() view returns (address)",
  "function implementation() view returns (address)",
  "function owner() view returns (address)",
  "function transferOwnership(address newOwner)",
];

describe("Safe Wallet Deployment", function async() {
  async function safeInitialize() {
    const [signer1, signer2] = await ethers.getSigners();

    const SafeSingleton = await ethers.getContractFactory("GnosisSafe");
    const safeSingleton = await SafeSingleton.deploy();
    await safeSingleton.waitForDeployment();

    const ProxyFactory = await ethers.getContractFactory(
      "GnosisSafeProxyFactory"
    );
    const proxyFactory = await ProxyFactory.deploy();
    await proxyFactory.waitForDeployment();

    return { signer1, signer2, safeSingleton, proxyFactory };
  }

  async function createTestWallet(
    singletonAddress: string,
    proxyFactory: GnosisSafeProxyFactory & {
      deploymentTransaction(): ContractTransactionResponse;
    },
    safeSingleton: GnosisSafe & {
      deploymentTransaction(): ContractTransactionResponse;
    },
    signers: string[]
  ) {
    const initializer = safeSingleton.interface.encodeFunctionData("setup", [
      signers,
      2,
      ethers.ZeroAddress,
      "0x",
      ethers.ZeroAddress,
      ethers.ZeroAddress,
      0,
      ethers.ZeroAddress,
    ]);

    const tx = await proxyFactory.createProxy(singletonAddress, initializer);
    const receipt = await tx.wait();

    if (!receipt) {
      return;
    }
    const proxyAddress = receipt.logs
      .map((log) => proxyFactory.interface.parseLog(log))
      .find((event) => event?.name === "ProxyCreation")?.args.proxy as string;

    const testSafeWallet = await ethers.getContractAt(
      "GnosisSafe",
      proxyAddress
    );

    return testSafeWallet;
  }

  it("should create a Safe wallet with two signers", async function () {
    const { signer1, signer2, safeSingleton, proxyFactory } =
      await safeInitialize();

    const singletonAddress = await safeSingleton.getAddress();

    const testSafeWallet = await createTestWallet(
      singletonAddress,
      proxyFactory,
      safeSingleton,
      [signer1.address, signer2.address]
    );

    const owners = await testSafeWallet!.getOwners();
    expect(owners.length).to.equal(2);
    expect(owners[0]).to.equal(signer1.address);
    expect(owners[1]).to.equal(signer2.address);
    expect(await testSafeWallet!.getThreshold()).to.equal(2);
  });

  describe("LBC Ownership change", function async() {
    it("should change the ownership of LBC", async function () {
      const { signer1, signer2, safeSingleton, proxyFactory } =
        await safeInitialize();

      const singletonAddress = await safeSingleton.getAddress();

      const testSafeWallet = await createTestWallet(
        singletonAddress,
        proxyFactory,
        safeSingleton,
        [signer1.address, signer2.address]
      );
      const deployed = await deployLbcProxy(hre.network.name, {
        verbose: false,
      });
      const proxyAddress = deployed.address;
      const lbc = await ethers.getContractAt(
        "LiquidityBridgeContract",
        proxyAddress
      );
      const proxyContract = await getContractAt(
        hre,
        TransparentProxyABI,
        proxyAddress
      );

      expect(await proxyContract.owner()).to.equal(signer1.address);

      const result = await lbc.queryFilter(lbc.getEvent("Initialized"));
      expect(deployed.deployed).to.be.eq(true);
      expect(result.length).length.equal(1);
      expect(await lbc.owner()).to.equal(signer1.address);

      const safeAddress = await testSafeWallet!.getAddress();

      await proxyContract.transferOwnership(safeAddress);

      expect(await proxyContract.owner()).to.equal(safeAddress);
    });
  });
});
