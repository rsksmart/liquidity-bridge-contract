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
|     **◯** _COLLATERAL_ADDER_          |      - |      - |   5,338 |     1 |       - |
|        *grantRole*                    |      - |      - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |        |        |         |       |         |
|     **◯** _getProvider_               |      - |      - |  21,368 |     1 |       - |
|     **◯** _getProviders_              |      - |      - |  43,913 |     1 |       - |
|     **◯** _isOperational_             | 38,744 | 41,131 |  39,555 |     3 |       - |
|        *register*                     |      - |      - | 240,678 |     2 |       - |
| **FlyoverDiscoveryFull**              |        |        |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |      - |      - |   5,382 |     1 |       - |
|     **◯** _getProvider_               |      - |      - |  21,517 |     1 |       - |
|     **◯** _getProviders_              |      - |      - |  31,461 |     1 |       - |
|        *grantRole*                    |      - |      - |  56,855 |     2 |       - |
|     **◯** _isOperational_             | 27,835 | 30,221 |  28,646 |     3 |       - |
|        *register*                     |      - |      - | 218,167 |     2 |       - |
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
| **CollateralManagementContract** |   - |   - | 1,593,014 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,621,177 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,563,567 |   8.5 % |       - |
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
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,338 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  21,368 |  23,990 |  22,679 |     2 |       - |
|     **◯** _getProviders_              |       - |       - |  68,340 |     1 |       - |
|     **◯** _isOperational_             |  21,263 |  41,218 |  34,125 |     6 |       - |
|        *register*                     | 199,082 | 240,678 | 219,880 |     4 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|     **◯** _getProvider_               |  21,517 |  24,136 |  22,827 |     2 |       - |
|     **◯** _getProviders_              |       - |       - |  51,560 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,822 |  30,287 |  23,368 |     6 |       - |
|        *register*                     | 178,981 | 218,167 | 198,574 |     4 |       - |
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
| **CollateralManagementContract** |   - |   - | 1,593,014 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,621,177 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,563,567 |   8.5 % |       - |
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
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,338 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  21,368 |  26,445 |  23,934 |     3 |       - |
|     **◯** _getProviders_              |       - |       - |  93,055 |     1 |       - |
|     **◯** _isOperational_             |  21,213 |  43,487 |  32,304 |     9 |       - |
|        *register*                     | 199,082 | 240,678 | 212,949 |     6 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|     **◯** _getProvider_               |  21,517 |  26,588 |  24,080 |     3 |       - |
|     **◯** _getProviders_              |       - |       - |  72,121 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,772 |  32,785 |  21,623 |     9 |       - |
|        *register*                     | 178,981 | 218,167 | 192,063 |     6 |       - |
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
| **CollateralManagementContract** |   - |   - | 1,593,014 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,621,177 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,563,567 |   8.5 % |       - |
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
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,338 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  21,368 |  28,900 |  25,176 |     4 |       - |
|     **◯** _getProviders_              |       - |       - | 119,363 |     1 |       - |
|     **◯** _isOperational_             |  21,213 |  48,284 |  35,906 |    12 |       - |
|        *register*                     | 199,082 | 240,678 | 215,607 |     8 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|     **◯** _getProvider_               |  21,517 |  29,040 |  25,320 |     4 |       - |
|     **◯** _getProviders_              |       - |       - |  95,317 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,772 |  38,036 |  25,256 |    12 |       - |
|        *register*                     | 178,981 | 218,167 | 194,314 |     8 |       - |
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
| **CollateralManagementContract** |   - |   - | 1,593,014 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,621,177 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,563,567 |   8.5 % |       - |
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
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,338 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  21,368 |  31,355 |  26,412 |     5 |       - |
|     **◯** _getProviders_              |       - |       - | 146,112 |     1 |       - |
|     **◯** _isOperational_             |  21,213 |  50,748 |  38,561 |    15 |       - |
|        *register*                     | 199,082 | 240,678 | 217,201 |    10 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|     **◯** _getProvider_               |  21,517 |  31,492 |  26,555 |     5 |       - |
|     **◯** _getProviders_              |       - |       - | 117,620 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,772 |  40,507 |  27,989 |    15 |       - |
|        *register*                     | 178,981 | 218,167 | 195,665 |    10 |       - |
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
| **CollateralManagementContract** |   - |   - | 1,593,014 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,621,177 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,563,567 |   8.5 % |       - |
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
