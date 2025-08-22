import { deployLbcProxy } from "../../scripts/deployment-utils/deploy-proxy";
import hre, { ethers, upgrades } from "hardhat";
import { upgradeLbcProxy } from "../../scripts/deployment-utils/upgrade-proxy";
import { LiquidityBridgeContractV2 } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { LP_COLLATERAL, ProviderType } from "./constants";
import { deployCollateralManagement } from "../collateral/fixtures";

export async function deployCollateralManagementAndDiscovery() {
  const { collateralManagement, signers, owner } =
    await deployCollateralManagement();
  const FlyoverDiscovery = await ethers.getContractFactory(
    "FlyoverDiscoveryContract"
  );

  const discovery = await upgrades.deployProxy(FlyoverDiscovery, [
    owner.address,
    await collateralManagement.getAddress(),
  ]);
  await collateralManagement
    .connect(owner)
    .grantRole(
      await collateralManagement.COLLATERAL_ADDER(),
      await discovery.getAddress()
    );

  const pegInLp = signers.pop();
  const pegOutLp = signers.pop();
  const fullLp = signers.pop();
  if (!pegInLp || !pegOutLp || !fullLp)
    throw new Error("LP can't be undefined");

  await discovery
    .connect(pegInLp)
    .register("Pegin Provider", "lp1.com", true, ProviderType.PegIn, {
      value: ethers.parseEther("0.6"),
    });
  await discovery
    .connect(pegOutLp)
    .register("PegOut Provider", "lp2.com", true, ProviderType.PegOut, {
      value: ethers.parseEther("0.6"),
    });
  await discovery
    .connect(fullLp)
    .register("Full Provider", "lp3.com", true, ProviderType.Both, {
      value: ethers.parseEther("1.2"),
    });

  return {
    collateralManagement,
    discovery,
    signers,
    owner,
    pegInLp,
    pegOutLp,
    fullLp,
  };
}

/**
 * Fixture that deploys the LBC contract and upgrades it to the latest version.
 * @returns { {
 *   lbc: LiquidityBridgeContractV2,
 *   lbcOwner: HardhatEthersSigner,
 *   accounts: HardhatEthersSigner[],
 *   bridgeMock: BridgeMock
 * } }
 * The returned object contains the following:
 * - lbc: The LiquidityBridgeContractV2 contract instance. Connected to the account 0 of the hardhat network.
 * - lbcOwner: The account 0 of the hardhat network.
 * - accounts: The accounts 1 to 19 of the hardhat network.
 * - bridgeMock: The BridgeMock contract instance. Connected to the account 0 of the hardhat network.
 */
export async function deployLbcFixture() {
  const network = hre.network.name;
  const deployInfo = await deployLbcProxy(network, { verbose: false });
  await upgradeLbcProxy(network, { verbose: false });
  const lbc: LiquidityBridgeContractV2 = await ethers.getContractAt(
    "LiquidityBridgeContractV2",
    deployInfo.address
  );
  const lbcOwner = await hre.ethers.provider.getSigner();
  const accounts = await ethers
    .getSigners()
    .then((signers) => signers.slice(1));

  const bridgeAddress = await lbc.bridge();
  const bridgeMock = await ethers.getContractAt("BridgeMock", bridgeAddress);
  return { lbc, lbcOwner, accounts, bridgeMock };
}

/**
 * Fixture that deploys the LBC contract and registers the last 3 hardhat signers as liquidity providers.
 * @returns { {
 *  lbc: LiquidityBridgeContractV2,
 *  liquidityProviders: {
 *  signer: HardhatEthersSigner,
 *    registerParams: Parameters<LiquidityBridgeContractV2["register"]>
 *  }[],
 *  lbcOwner: HardhatEthersSigner,
 *  bridgeMock: BridgeMock,
 *  accounts: HardhatEthersSigner[]
 * } }
 * The returned object contains the following:
 * - lbc: The LiquidityBridgeContractV2 contract instance. Connected to the account 0 of the hardhat network.
 * - liquidityProviders: An array of objects containing the signer and the parameters to register as a liquidity provider.
 *   the signers of the liquidity providers are the last 3 signers of the hardhat network accounts.
 * - lbcOwner: The account 0 of the hardhat network.
 * - bridgeMock: The BridgeMock contract instance. Connected to the account 0 of the hardhat network.
 * - accounts: The accounts 1 to 16 of the hardhat network.
 */
export async function deployLbcWithProvidersFixture() {
  const network = hre.network.name;
  const deployInfo = await deployLbcProxy(network, { verbose: false });
  await upgradeLbcProxy(network, { verbose: false });
  let lbc: LiquidityBridgeContractV2 = await ethers.getContractAt(
    "LiquidityBridgeContractV2",
    deployInfo.address
  );

  const bridgeMock = await lbc
    .bridge()
    .then((bridgeAddress) => ethers.getContractAt("BridgeMock", bridgeAddress));

  const signers = await ethers.getSigners();
  const accounts = signers.slice(1, -3);
  const lpSigners = signers.splice(-3);
  const liquidityProviders: {
    signer: HardhatEthersSigner;
    registerParams: Parameters<LiquidityBridgeContractV2["register"]>;
  }[] = [
    {
      signer: lpSigners[0],
      registerParams: [
        "First LP",
        "http://localhost/api1",
        true,
        "both",
        { value: LP_COLLATERAL },
      ],
    },
    {
      signer: lpSigners[1],
      registerParams: [
        "Second LP",
        "http://localhost/api2",
        true,
        "pegin",
        { value: LP_COLLATERAL / 2n },
      ],
    },
    {
      signer: lpSigners[2],
      registerParams: [
        "Third LP",
        "http://localhost/api3",
        true,
        "pegout",
        { value: LP_COLLATERAL / 2n },
      ],
    },
  ];

  for (const provider of liquidityProviders) {
    lbc = lbc.connect(provider.signer);
    const registerTx = await lbc.register(...provider.registerParams);
    await registerTx.wait();
  }

  const lbcOwner = await hre.ethers.provider.getSigner();
  return { lbc, liquidityProviders, lbcOwner, bridgeMock, accounts };
}
