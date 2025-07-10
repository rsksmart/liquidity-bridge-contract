# Discovery executions with different number of LPs

## One liquidity provider

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |    Min |    Max |     Avg | Calls | usd avg |
| :------------------------------------ | -----: | -----: | ------: | ----: | ------: |
| **CollateralManagementContract**      |        |        |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |      - |      - |   5,382 |     1 |       - |
|        *grantRole*                    |      - |      - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |        |        |         |       |         |
|     **◯** _getProvider_               |      - |      - |  19,198 |     1 |       - |
|     **◯** _getProviders_              |      - |      - |  38,833 |     1 |       - |
|     **◯** _isOperational_             | 36,182 | 39,016 |  37,291 |     3 |       - |
|        *register*                     |      - |      - | 231,185 |     2 |       - |
| **FlyoverDiscoveryFull**              |        |        |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |      - |      - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |      - |      - |  19,396 |     1 |       - |
|     **◯** _getProviders_              |      - |      - |  29,161 |     1 |       - |
|        *grantRole*                    |      - |      - |  56,855 |     2 |       - |
|     **◯** _isOperational_             | 25,717 | 28,106 |  26,530 |     3 |       - |
|        *register*                     |      - |      - | 196,237 |     2 |       - |
| **LiquidityBridgeContractV2**         |        |        |         |       |         |
|     **◯** _getProvider_               |      - |      - |  24,376 |     1 |       - |
|     **◯** _getProviders_              |      - |      - |  31,679 |     1 |       - |
|     **◯** _isOperational_             |      - |      - |  12,518 |     1 |       - |
|     **◯** _isOperationalForPegout_    |      - |      - |  12,540 |     1 |       - |
|        *register*                     |      - |      - | 239,737 |     2 |       - |
| **ProxyAdmin**                        |        |        |         |       |         |
|     **◯** _owner_                     |      - |      - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |      - |      - |     567 |     1 |       - |
|        *upgradeAndCall*               |      - |      - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,576,388 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,635,403 |   5.5 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,552,304 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |

## Two liquidity providers

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |     Min |     Max |     Avg | Calls | usd avg |
| :------------------------------------ | ------: | ------: | ------: | ----: | ------: |
| **CollateralManagementContract**      |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  19,198 |  21,643 |  20,421 |     2 |       - |
|     **◯** _getProviders_              |       - |       - |  58,176 |     1 |       - |
|     **◯** _isOperational_             |  21,307 |  39,104 |  32,655 |     6 |       - |
|        *register*                     | 183,476 | 231,185 | 207,331 |     4 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |  19,396 |  22,007 |  20,702 |     2 |       - |
|     **◯** _getProviders_              |       - |       - |  46,945 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,844 |  28,169 |  21,964 |     6 |       - |
|        *register*                     | 157,051 | 196,237 | 176,644 |     4 |       - |
| **LiquidityBridgeContractV2**         |         |         |         |       |         |
|     **◯** _getProvider_               |  24,376 |  26,825 |  25,601 |     2 |       - |
|     **◯** _getProviders_              |       - |       - |  54,330 |     1 |       - |
|     **◯** _isOperational_             |       - |       - |  12,518 |     2 |       - |
|     **◯** _isOperationalForPegout_    |   7,905 |  12,540 |  10,223 |     2 |       - |
|        *register*                     | 200,944 | 239,737 | 220,341 |     4 |       - |
| **ProxyAdmin**                        |         |         |         |       |         |
|     **◯** _owner_                     |       - |       - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |       - |       - |     567 |     1 |       - |
|        *upgradeAndCall*               |       - |       - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,576,388 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,635,403 |   5.5 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,552,304 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |

## Three liquidity providers

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |     Min |     Max |     Avg | Calls | usd avg |
| :------------------------------------ | ------: | ------: | ------: | ----: | ------: |
| **CollateralManagementContract**      |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  19,198 |  24,266 |  21,702 |     3 |       - |
|     **◯** _getProviders_              |       - |       - |  77,342 |     1 |       - |
|     **◯** _isOperational_             |  21,257 |  41,624 |  31,127 |     9 |       - |
|        *register*                     | 183,284 | 231,185 | 199,315 |     6 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |  19,396 |  24,459 |  21,954 |     3 |       - |
|     **◯** _getProviders_              |       - |       - |  65,154 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,794 |  30,670 |  20,457 |     9 |       - |
|        *register*                     | 157,051 | 196,237 | 170,133 |     6 |       - |
| **LiquidityBridgeContractV2**         |         |         |         |       |         |
|     **◯** _getProvider_               |  24,376 |  29,274 |  26,825 |     3 |       - |
|     **◯** _getProviders_              |       - |       - |  80,551 |     1 |       - |
|     **◯** _isOperational_             |   7,883 |  12,518 |  10,973 |     3 |       - |
|     **◯** _isOperationalForPegout_    |   7,905 |  12,540 |  10,995 |     3 |       - |
|        *register*                     | 200,944 | 239,737 | 214,201 |     6 |       - |
| **ProxyAdmin**                        |         |         |         |       |         |
|     **◯** _owner_                     |       - |       - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |       - |       - |     567 |     1 |       - |
|        *upgradeAndCall*               |       - |       - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,576,388 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,635,403 |   5.5 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,552,304 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |

## Four liquidity providers

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |     Min |     Max |     Avg | Calls | usd avg |
| :------------------------------------ | ------: | ------: | ------: | ----: | ------: |
| **CollateralManagementContract**      |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  19,198 |  26,721 |  22,957 |     4 |       - |
|     **◯** _getProviders_              |       - |       - |  99,221 |     1 |       - |
|     **◯** _isOperational_             |  21,257 |  46,178 |  34,497 |    12 |       - |
|        *register*                     | 183,284 | 231,185 | 203,008 |     8 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |  19,396 |  26,911 |  23,193 |     4 |       - |
|     **◯** _getProviders_              |       - |       - |  85,983 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,794 |  35,462 |  23,814 |    12 |       - |
|        *register*                     | 157,051 | 196,237 | 172,384 |     8 |       - |
| **LiquidityBridgeContractV2**         |         |         |         |       |         |
|     **◯** _getProvider_               |  24,376 |  31,723 |  28,050 |     4 |       - |
|     **◯** _getProviders_              |       - |       - | 103,386 |     1 |       - |
|     **◯** _isOperational_             |   7,883 |  12,518 |  11,359 |     4 |       - |
|     **◯** _isOperationalForPegout_    |   7,905 |  12,540 |  11,381 |     4 |       - |
|        *register*                     | 200,944 | 239,737 | 216,310 |     8 |       - |
| **ProxyAdmin**                        |         |         |         |       |         |
|     **◯** _owner_                     |       - |       - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |       - |       - |     567 |     1 |       - |
|        *upgradeAndCall*               |       - |       - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,576,388 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,635,403 |   5.5 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,552,304 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |

## Five liquidity providers

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |     Min |     Max |     Avg | Calls | usd avg |
| :------------------------------------ | ------: | ------: | ------: | ----: | ------: |
| **CollateralManagementContract**      |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  19,198 |  29,176 |  24,201 |     5 |       - |
|     **◯** _getProviders_              |       - |       - | 120,180 |     1 |       - |
|     **◯** _isOperational_             |  21,257 |  48,642 |  37,012 |    15 |       - |
|        *register*                     | 183,284 | 231,185 | 205,223 |    10 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |  19,396 |  29,363 |  24,427 |     5 |       - |
|     **◯** _getProviders_              |       - |       - | 106,482 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,794 |  38,375 |  26,350 |    15 |       - |
|        *register*                     | 157,051 | 196,237 | 173,735 |    10 |       - |
| **LiquidityBridgeContractV2**         |         |         |         |       |         |
|     **◯** _getProvider_               |  24,376 |  34,172 |  29,274 |     5 |       - |
|     **◯** _getProviders_              |       - |       - | 125,661 |     1 |       - |
|     **◯** _isOperational_             |   7,883 |  12,518 |  11,591 |     5 |       - |
|     **◯** _isOperationalForPegout_    |   7,905 |  12,540 |  11,613 |     5 |       - |
|        *register*                     | 200,944 | 239,737 | 217,576 |    10 |       - |
| **ProxyAdmin**                        |         |         |         |       |         |
|     **◯** _owner_                     |       - |       - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |       - |       - |     567 |     1 |       - |
|        *upgradeAndCall*               |       - |       - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,576,388 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,635,403 |   5.5 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,552,304 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |
