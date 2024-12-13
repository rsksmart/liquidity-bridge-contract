import { readFileSync, writeFileSync } from "fs";

/**
 * Layout of the addresses.json file. Consist of a map of networks, each network has a map of
 * contracts and the value of that contract has the structure defined in {@link DeployedContractInfo}.
 */
export interface DeploymentConfig {
  [network: string]: {
    [contract: string]: DeployedContractInfo;
  };
}

/**
 * This interface holds the information of a deployed contract in the addresses.json file.
 *
 * @param deployed - Indicates if the contract has been deployed or not, if the contract is
 * in the file it usually means it was already deployed. But this value can be set to false
 * to execute a re deployment.
 *
 * @param address - The address of the deployed contract.
 */
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

/**
 * Reads the addresses.json file and returns its content as a {@link DeploymentConfig} object.
 *
 * @returns { DeploymentConfig } The content of the addresses.json file.
 */
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

/**
 * Is the function that deploys a contract and updates the addresses.json file. Every deployment
 * should call this function at some point in order to save the addresses. If the contract figures
 * as deployed in the addresses.json file, it will not be deployed again.
 *
 * @param name The name of the contract to deploy as it should appear in the addresses.json file.
 * @param network The name of the network to deploy the contract to as it appears in the addresses.json file.
 * @param act The deployment function itself, this function should return the address of the deployed contract.
 *
 * @returns { Promise<DeployedContractInfo> } The information of the deployed contract.
 */
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
