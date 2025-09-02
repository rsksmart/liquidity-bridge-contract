import hre, { upgrades } from "hardhat";
import { ethers } from "hardhat";
import {
  CollateralManagementContract,
  FlyoverDiscovery,
} from "../typechain-types";
import { deploy } from "../scripts/deployment-utils/deploy";

describe("FlyoverDiscovery benchmark", () => {
  async function deployFlyoverDiscovery() {
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
          [owner.address, 5000n, ethers.parseEther("0.03"), 60n, 10n]
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

    const discoveryProxy = "FlyoverDiscovery";
    const discoveryDeploy = await deploy(discoveryProxy, network, async () => {
      const FlyoverDiscovery = await ethers.getContractFactory(discoveryProxy);
      const deployed = await upgrades.deployProxy(FlyoverDiscovery, [
        owner.address,
        5000n,
        collateralManagementDeploy.address!,
      ]);
      const address = await deployed.getAddress();
      return address;
    });
    const discovery: FlyoverDiscovery = await ethers.getContractAt(
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

    let { discovery } = await deployFlyoverDiscovery();

    const providersData = [
      {
        account: accounts[1],
        providerType: 2, // Both
        providerAddress: accounts[1].address,
        apiBaseUrl: "https://api.flyover1.com",
        name: "Flyover1",
      },
      {
        account: accounts[2],
        providerType: 0, // PegIn
        providerAddress: accounts[2].address,
        apiBaseUrl: "https://api.flyover2.com",
        name: "Flyover2",
      },
      {
        account: accounts[3],
        providerType: 1, // PegOut
        providerAddress: accounts[3].address,
        apiBaseUrl: "https://api.flyover3.com",
        name: "Flyover3",
      },
      {
        account: accounts[4],
        providerType: 2, // Both
        providerAddress: accounts[4].address,
        apiBaseUrl: "https://api.flyover4.com",
        name: "Flyover4",
      },
      {
        account: accounts[5],
        providerType: 2, // Both
        providerAddress: accounts[5].address,
        apiBaseUrl: "https://api.flyover5.com",
        name: "Flyover5",
      },
    ];

    for (const providerData of providersData) {
      const { providerType, apiBaseUrl, account, name } = providerData;

      discovery = discovery.connect(account);
      await discovery
        .register(name, apiBaseUrl, true, providerType, {
          value: ethers.parseEther("0.06"),
        })
        .then((tx) => tx.wait());
    }

    console.log(
      "-------------------------------- GET PROVIDERS --------------------------------"
    );
    const discoveryProviders = await discovery.getProviders();
    console.log(discoveryProviders);

    console.log(
      "-------------------------------- GET PROVIDER --------------------------------"
    );
    for (const account of providersData) {
      const result = await discovery.getProvider(account.providerAddress);
      console.log(result);
    }
    console.log(
      "-------------------------------- IS OPERATIONAL --------------------------------"
    );
    for (const account of providersData) {
      const result = await discovery.isOperational(account.providerAddress);
      console.log(account.name, "operational:", result);
    }
  });
});
