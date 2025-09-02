import { upgrades, ethers } from "hardhat";
import { ProviderType } from "../utils/constants";
import { deployCollateralManagement } from "../collateral/fixtures";

export async function deployDiscoveryFixture() {
  const FlyoverDiscovery = await ethers.getContractFactory("FlyoverDiscovery");

  // Use the existing CollateralManagement fixture instead of manual deployment
  const { collateralManagement, signers, owner } =
    await deployCollateralManagement();

  const MIN_COLLATERAL = ethers.parseEther("0.6");
  const INITIAL_DELAY = 500n;

  const discovery = await upgrades.deployProxy(FlyoverDiscovery, [
    owner.address,
    INITIAL_DELAY,
    await collateralManagement.getAddress(),
  ]);

  // Allow owner to add collateral directly for test setup
  await collateralManagement
    .connect(owner)
    .grantRole(await collateralManagement.COLLATERAL_ADDER(), owner.address);

  // Grant COLLATERAL_ADDER role to FlyoverDiscovery contract
  await collateralManagement
    .connect(owner)
    .grantRole(
      await collateralManagement.COLLATERAL_ADDER(),
      await discovery.getAddress()
    );

  return {
    discovery,
    collateralManagement,
    owner,
    signers,
    MIN_COLLATERAL,
  };
}

export async function deployDiscoveryWithProvidersFixture() {
  const { discovery, collateralManagement, owner, signers, MIN_COLLATERAL } =
    await deployDiscoveryFixture();

  const pegInLp = signers.pop();
  const pegOutLp = signers.pop();
  const fullLp = signers.pop();
  if (!pegInLp || !pegOutLp || !fullLp)
    throw new Error("LP can't be undefined");

  // Register providers (Discovery now handles collateral addition automatically)
  await discovery
    .connect(pegInLp)
    .register("Pegin Provider", "lp1.com", true, ProviderType.PegIn, {
      value: MIN_COLLATERAL,
    });
  await discovery
    .connect(pegOutLp)
    .register("PegOut Provider", "lp2.com", true, ProviderType.PegOut, {
      value: MIN_COLLATERAL,
    });
  await discovery
    .connect(fullLp)
    .register("Full Provider", "lp3.com", true, ProviderType.Both, {
      value: MIN_COLLATERAL * 2n,
    });

  return {
    discovery,
    collateralManagement,
    owner,
    pegInLp,
    pegOutLp,
    fullLp,
    signers,
    MIN_COLLATERAL,
  };
}
