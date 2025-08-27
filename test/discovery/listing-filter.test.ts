import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import {
  deployDiscoveryWithProvidersFixture,
  deployDiscoveryFixture,
} from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery listing filters", () => {
  it("lists only enabled providers", async () => {
    const { discovery, pegOutLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );

    let providers = await discovery.getProviders();
    expect(providers.map((p) => p.id)).to.deep.equal([1n, 2n, 3n]);

    // Disable provider with id 2
    await discovery.connect(pegOutLp).setProviderStatus(2, false);

    providers = await discovery.getProviders();
    expect(providers.map((p) => p.id)).to.deep.equal([1n, 3n]);
  });
});

describe("FlyoverDiscovery listing edge cases", () => {
  it("does not list providers without sufficient collateral until collateral is added", async () => {
    const { discovery, collateralManagement, signers, owner, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-1)!;

    await discovery
      .connect(lp)
      .register("N", "U", true, ProviderType.PegIn, { value: MIN_COLLATERAL });

    let providers = await discovery.getProviders();
    // Not listed because collateral management not yet funded for this LP
    expect(providers.length).to.equal(0);

    await collateralManagement
      .connect(owner)
      .addPegInCollateralTo(lp.address, { value: MIN_COLLATERAL });

    providers = await discovery.getProviders();
    expect(providers.length).to.equal(1);
    expect(providers[0].providerAddress).to.equal(lp.address);
  });

  it("returns providers ordered by id", async () => {
    const { discovery, collateralManagement, owner, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const [a, b, c] = signers.slice(-3);

    await discovery
      .connect(a)
      .register("A", "U1", true, ProviderType.PegIn, { value: MIN_COLLATERAL });
    await discovery
      .connect(b)
      .register("B", "U2", true, ProviderType.PegIn, { value: MIN_COLLATERAL });
    await discovery
      .connect(c)
      .register("C", "U3", true, ProviderType.PegIn, { value: MIN_COLLATERAL });

    // fund collateral to list them
    for (const lp of [a, b, c]) {
      await collateralManagement
        .connect(owner)
        .addPegInCollateralTo(lp.address, { value: MIN_COLLATERAL });
    }

    const providers = await discovery.getProviders();
    expect(providers.map((p) => p.id)).to.deep.equal([1n, 2n, 3n]);
  });
});
