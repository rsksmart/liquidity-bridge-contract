import { readFileSync, writeFileSync } from "fs";

export interface DeploymentConfig {
  [network: string]: {
    [contract: string]: DeployedContractInfo;
  };
}

export interface DeployedContractInfo {
  deployed: boolean;
  address?: string;
}

type deployFunction = (
  name: string,
  network: string,
  act: () => Promise<string>
) => Promise<DeployedContractInfo>;

const ADDRESSES_FILE = "addresses.json";
export const LOCAL_NETWORK = "rskRegtest";
const UNIT_TEST_NETWORK = "hardhat";

const testConfig: DeploymentConfig = { [UNIT_TEST_NETWORK]: {} };
export const read: () => DeploymentConfig = () =>
  Object.keys(testConfig[UNIT_TEST_NETWORK]).length > 0
    ? testConfig
    : JSON.parse(readFileSync(ADDRESSES_FILE).toString());
const write = (newConfig: DeploymentConfig) => {
  const oldConfig = read();
  writeFileSync(
    ADDRESSES_FILE,
    JSON.stringify({ ...oldConfig, ...newConfig }, null, 2)
  );
};

export const deploy: deployFunction = async (
  name: string,
  network: string,
  act: () => Promise<string>
) => {
  const oldConfig = read();

  if (!oldConfig[network]) {
    oldConfig[network] = {};
  }

  if (!oldConfig[network][name]) {
    oldConfig[network][name] = { deployed: false };
  }

  if (network === UNIT_TEST_NETWORK) {
    const address = await act();
    testConfig[UNIT_TEST_NETWORK][name] = { deployed: true, address: address };
    return testConfig[network][name];
  }

  if (!oldConfig[network][name].deployed || network === LOCAL_NETWORK) {
    const address = await act();
    oldConfig[network][name].deployed = true;
    oldConfig[network][name].address = address;
    write(oldConfig);
  } else {
    console.warn(
      `${name} has already be deployed [address: ${oldConfig[network][name].address}]. If you want to deploy it, please set deployed attribute to false on addresses.json file.`
    );
  }
  return read()[network][name];
};
