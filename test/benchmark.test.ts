import hre, { upgrades } from "hardhat";
import { ethers } from "hardhat";
import { deployLbcProxy } from "../scripts/deployment-utils/deploy-proxy";
import { upgradeLbcProxy } from "../scripts/deployment-utils/upgrade-proxy";
import {
  CollateralManagementContract,
  FlyoverDiscoveryContract,
  FlyoverDiscoveryFull,
  LiquidityBridgeContractV2,
} from "../typechain-types";
import { deploy } from "../scripts/deployment-utils/deploy";

describe("FlyoverDiscovery benchmark", () => {
  async function deployLbc() {
    const network = hre.network.name;
    const deployInfo = await deployLbcProxy(network, { verbose: false });
    await upgradeLbcProxy(network, { verbose: false });
    const lbc: LiquidityBridgeContractV2 = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      deployInfo.address
    );
    const lbcOwner = await hre.ethers.provider.getSigner();

    return { lbc, lbcOwner };
  }

  async function deployDiscoveryFull() {
    const network = hre.network.name;
    const proxyName = "FlyoverDiscoveryFull";
    const owner = await hre.ethers.provider.getSigner();
    const deployed = await deploy(proxyName, network, async () => {
      const FlyoverDiscoveryFull = await ethers.getContractFactory(proxyName);
      const deployed = await upgrades.deployProxy(FlyoverDiscoveryFull, [
        owner.address,
        5000n,
        ethers.parseEther("0.03"),
        60n,
      ]);
      const address = await deployed.getAddress();
      return address;
    });
    const discovery: FlyoverDiscoveryFull = await ethers.getContractAt(
      proxyName,
      deployed.address!
    );
    const collateralAdder = await discovery.COLLATERAL_ADDER();
    await discovery
      .grantRole(collateralAdder, owner.address)
      .then((tx) => tx.wait());
    return { discovery, owner };
  }

  async function deployDiscoverySplit() {
    const network = hre.network.name;
    const collateralManagementProxy = "CollateralManagementContract";
    const owner = await hre.ethers.provider.getSigner();
    const collateralManagementDeploy = await deploy(
      collateralManagementProxy,
      network,
      async () => {
        const CollateralManagementContract = await ethers.getContractFactory(
          collateralManagementProxy
        );
        const deployed = await upgrades.deployProxy(
          CollateralManagementContract,
          [owner.address, 5000n, ethers.parseEther("0.03"), 60n]
        );
        const address = await deployed.getAddress();
        return address;
      }
    );
    const collateralManagement: CollateralManagementContract =
      await ethers.getContractAt(
        collateralManagementProxy,
        collateralManagementDeploy.address!
      );

    const discoveryProxy = "FlyoverDiscoveryContract";
    const discoveryDeploy = await deploy(discoveryProxy, network, async () => {
      const FlyoverDiscovery = await ethers.getContractFactory(discoveryProxy);
      const deployed = await upgrades.deployProxy(FlyoverDiscovery, [
        owner.address,
        collateralManagementDeploy.address,
      ]);
      const address = await deployed.getAddress();
      return address;
    });
    const discovery: FlyoverDiscoveryContract = await ethers.getContractAt(
      discoveryProxy,
      discoveryDeploy.address!
    );
    const collateralAdder = await collateralManagement.COLLATERAL_ADDER();
    await collateralManagement
      .grantRole(collateralAdder, discoveryDeploy.address!)
      .then((tx) => tx.wait());
    return { collateralManagement, discovery, owner };
  }

  it("register and fetch a LP of each type", async () => {
    const accounts = await ethers
      .getSigners()
      .then((signers) => signers.slice(1)); // 1st is the owner

    let { lbc } = await deployLbc();
    let { discovery: discoveryFull } = await deployDiscoveryFull();
    let { discovery } = await deployDiscoverySplit();

    const providersData = [
      {
        account: accounts[1],
        providerType: 2,
        oldProviderType: "both",
        providerAddress: accounts[1].address,
        apiBaseUrl: "https://api.flyover1.com",
        name: "Flyover1",
      },
      {
        account: accounts[2],
        providerType: 0,
        oldProviderType: "pegin",
        providerAddress: accounts[2].address,
        apiBaseUrl: "https://api.flyover2.com",
        name: "Flyover2",
      },
      {
        account: accounts[3],
        providerType: 1,
        oldProviderType: "pegout",
        providerAddress: accounts[3].address,
        apiBaseUrl: "https://api.flyover3.com",
        name: "Flyover3",
      },
      {
        account: accounts[4],
        providerType: 2,
        oldProviderType: "both",
        providerAddress: accounts[4].address,
        apiBaseUrl: "https://api.flyover4.com",
        name: "Flyover4",
      },
      {
        account: accounts[5],
        providerType: 2,
        oldProviderType: "both",
        providerAddress: accounts[5].address,
        apiBaseUrl: "https://api.flyover5.com",
        name: "Flyover5",
      },
    ];

    for (const providerData of providersData) {
      const { providerType, oldProviderType, apiBaseUrl, account, name } =
        providerData;

      discovery = discovery.connect(account);
      await discovery
        .register(name, apiBaseUrl, true, providerType, {
          value: ethers.parseEther("0.06"),
        })
        .then((tx) => tx.wait());
      discoveryFull = discoveryFull.connect(account);
      await discoveryFull
        .register(name, apiBaseUrl, true, providerType, {
          value: ethers.parseEther("0.06"),
        })
        .then((tx) => tx.wait());
      lbc = lbc.connect(account);
      await lbc
        .register(name, apiBaseUrl, true, oldProviderType, {
          value: ethers.parseEther("0.06"),
        })
        .then((tx) => tx.wait());
    }

    console.log(
      "-------------------------------- GET PROVIDERS --------------------------------"
    );
    console.log(
      "-------------------------------- DISCOVERY --------------------------------"
    );
    const discoveryProviders = await discovery.getProviders();
    console.log(discoveryProviders);
    console.log(
      "-------------------------------- DISCOVERY FULL --------------------------------"
    );
    const discoveryFullProviders = await discoveryFull.getProviders();
    console.log(discoveryFullProviders);
    console.log(
      "-------------------------------- LBC --------------------------------"
    );
    const lbcProviders = await lbc.getProviders();
    console.log(lbcProviders);

    console.log(
      "-------------------------------- GET PROVIDER --------------------------------"
    );
    console.log(
      "-------------------------------- DISCOVERY --------------------------------"
    );
    for (const account of providersData) {
      const result = await discovery.getProvider(account.providerAddress);
      console.log(result);
    }
    console.log(
      "-------------------------------- DISCOVERY FULL --------------------------------"
    );
    for (const account of providersData) {
      const result = await discoveryFull.getProvider(account.providerAddress);
      console.log(result);
    }
    console.log(
      "-------------------------------- LBC --------------------------------"
    );
    for (const account of providersData) {
      const result = await lbc.getProvider(account.providerAddress);
      console.log(result);
    }
    console.log(
      "-------------------------------- IS OPERATIONAL --------------------------------"
    );
    const types = [
      { new: 0, old: "pegin" },
      { new: 1, old: "pegout" },
      { new: 2, old: "both" },
    ];
    console.log(
      "-------------------------------- DISCOVERY --------------------------------"
    );
    for (const account of providersData) {
      for (const type of types) {
        const result = await discovery.isOperational(
          type.new,
          account.providerAddress
        );
        console.log(account.name, type.old, result);
      }
    }
    console.log(
      "-------------------------------- DISCOVERY FULL --------------------------------"
    );
    for (const account of providersData) {
      for (const type of types) {
        const result = await discoveryFull.isOperational(
          type.new,
          account.providerAddress
        );
        console.log(account.name, type.old, result);
      }
    }
    console.log(
      "-------------------------------- LBC --------------------------------"
    );
    for (const account of providersData) {
      const peginResult = await lbc.isOperational(account.providerAddress);
      const pegoutResult = await lbc.isOperationalForPegout(
        account.providerAddress
      );
      console.log(account.name, "pegin", peginResult);
      console.log(account.name, "pegout", pegoutResult);
    }
  });
});
