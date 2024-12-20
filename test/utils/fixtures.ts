import { deployLbcProxy } from "../../scripts/deployment-utils/deploy-proxy";
import hre, { ethers } from "hardhat";
import { upgradeLbcProxy } from "../../scripts/deployment-utils/upgrade-proxy";
import { LiquidityBridgeContractV2 } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { LP_COLLATERAL } from "./constants";

/**
 * Fixture that deploys the LBC contract and upgrades it to the latest version.
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

  const bridgeMock = await lbc
    .getBridgeAddress()
    .then((bridgeAddress) => ethers.getContractAt("BridgeMock", bridgeAddress));
  return { lbc, lbcOwner, accounts, bridgeMock };
}

/**
 * Fixture that deploys the LBC contract and registers the last 3 ethers signers as liquidity providers.
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
    .getBridgeAddress()
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
    lbc = await lbc.connect(provider.signer);
    const registerTx = await lbc.register(...provider.registerParams);
    await registerTx.wait();
  }

  const lbcOwner = await hre.ethers.provider.getSigner();
  return { lbc, liquidityProviders, lbcOwner, bridgeMock, accounts };
}
