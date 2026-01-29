# VERITE-Harness

Solidity Harness for VERITE Fuzzer - DeFi Action Implementations

[![Solidity](https://img.shields.io/badge/solidity-%5E0.8.20-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/foundry-latest-orange.svg)](https://getfoundry.sh/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Overview

VERITE-Harness is a Solidity smart contract that serves as the execution harness for [VERITE-Lab](https://github.com/shoheigorila/verite-lab). It implements a standardized set of DeFi actions that the fuzzer can compose into attack sequences.

The harness provides:
- **11 DeFi actions** covering swaps, liquidity, flash loans, and token operations
- **Action specification registry** for dynamic action discovery
- **Basis points (BPS) interface** for percentage-based operations
- **Flash loan callbacks** for both Uniswap V2 and V3

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AttackHarness.sol                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                      Action Registry                            │ │
│  │  getActions() → ActionSpec[]                                   │ │
│  │  - id, selector, argc, argKinds                                │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  │
│  │   ERC20     │  │  Uniswap    │  │  Uniswap    │  │   WETH    │  │
│  │  Actions    │  │    V2       │  │    V3       │  │  Actions  │  │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├───────────┤  │
│  │ A1:Transfer │  │ A2:Swap     │  │ A6:Swap     │  │ A10:Wrap  │  │
│  │             │  │ A3:AddLiq   │  │ A7:Mint     │  │ A11:Unwrap│  │
│  │             │  │ A4:RemoveLiq│  │ A8:Collect  │  │           │  │
│  │             │  │ A5:Flash    │  │ A9:Flash    │  │           │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    Flash Loan Callbacks                         │ │
│  │  uniswapV2Call()  │  uniswapV3FlashCallback()                  │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Actions

### Action Specification

Each action is defined with:
- **id**: Unique identifier (uint32)
- **selector**: Function selector (bytes4)
- **argc**: Number of arguments (uint8)
- **argKinds**: Array of argument types

```solidity
struct ActionSpec {
    uint32 id;
    bytes4 selector;
    uint8 argc;
    ArgKind[] argKinds;
}

enum ArgKind {
    U256,      // 0: Arbitrary uint256
    Bps,       // 1: Basis points (0-10000)
    Token,     // 2: ERC20 token address
    Address,   // 3: Arbitrary address
    Int24,     // 4: Signed 24-bit integer (ticks)
    Bool       // 5: Boolean
}
```

### Implemented Actions

| ID | Name | Function Signature | Description |
|----|------|-------------------|-------------|
| 1 | ERC20 Transfer | `erc20TransferBps(address,address,uint16)` | Transfer % of token balance |
| 2 | V2 Swap | `v2SwapExactInBps(address,address,address,uint16,uint16)` | Swap on Uniswap V2 |
| 3 | V2 Add Liquidity | `v2AddLiqBps(address,address,address,uint16,uint16)` | Add liquidity to V2 pool |
| 4 | V2 Remove Liquidity | `v2RemoveLiqBps(address,address,uint16)` | Remove liquidity from V2 |
| 5 | V2 Flash Loan | `flashloanV2(address,address,uint16)` | Borrow via V2 swap |
| 6 | V3 Swap | `v3SwapExactIn(address,address,address,uint24,uint16,uint160)` | Swap on Uniswap V3 |
| 7 | V3 Mint Position | `v3MintPosition(address,address,address,uint24,int24,int24,uint16,uint16)` | Create V3 LP position |
| 8 | V3 Collect Fees | `v3CollectFees(address,uint256)` | Collect fees from V3 position |
| 9 | V3 Flash Loan | `flashloanV3(address,address,address,uint16,uint16)` | V3 flash loan |
| 10 | Wrap ETH | `wrapEth(address,uint16)` | Convert ETH to WETH |
| 11 | Unwrap ETH | `unwrapEth(address,uint16)` | Convert WETH to ETH |

## Basis Points (BPS)

All percentage-based operations use basis points for precision:

| BPS Value | Percentage |
|-----------|------------|
| 10000 | 100% |
| 5000 | 50% |
| 1000 | 10% |
| 100 | 1% |
| 1 | 0.01% |

```solidity
uint16 constant BPS_MAX = 10000;

// Calculate amount from balance using BPS
function applyBps(uint256 balance, uint16 bps) internal pure returns (uint256) {
    return (balance * bps) / BPS_MAX;
}
```

## Installation

### Prerequisites

- [Foundry](https://getfoundry.sh/)
- Git

### Setup

```bash
# Clone the repository
git clone https://github.com/shoheigorila/verite-harness.git
cd verite-harness

# Install dependencies
forge install

# Build
forge build

# Run tests
forge test
```

## Usage

### Deploying the Harness

```solidity
// Deploy the harness
AttackHarness harness = new AttackHarness();

// Query available actions
AttackHarness.ActionSpec[] memory actions = harness.getActions();

// Execute an action (example: swap 50% of WETH to USDC)
harness.v2SwapExactInBps(
    0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2 Router
    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
    5000,  // 50% of balance
    4500   // Min 45% output (slippage protection)
);
```

### Integrating with VERITE-Lab

The harness is automatically deployed by VERITE-Lab fuzzer. The fuzzer:

1. Deploys `AttackHarness` contract
2. Calls `getActions()` to discover available actions
3. Generates action sequences using `ActionIR`
4. Encodes calls using the action registry
5. Executes sequences and measures profit

## Project Structure

```
verite-harness/
├── src/
│   ├── AttackHarness.sol       # Main harness contract
│   └── interfaces/
│       ├── IERC20.sol          # ERC20 interface
│       ├── IUniswapV2.sol      # Uniswap V2 interfaces
│       ├── IUniswapV3.sol      # Uniswap V3 interfaces
│       └── IWETH.sol           # WETH interface
├── test/
│   └── AttackHarness.t.sol     # Harness tests
├── foundry.toml                # Foundry configuration
└── README.md
```

## Interfaces

### IUniswapV2.sol

```solidity
interface IUniswapV2Router02 {
    function swapExactTokensForTokens(...) external returns (uint256[] memory);
    function addLiquidity(...) external returns (uint256, uint256, uint256);
    function removeLiquidity(...) external returns (uint256, uint256);
}

interface IUniswapV2Pair {
    function swap(uint256, uint256, address, bytes calldata) external;
    function getReserves() external view returns (uint112, uint112, uint32);
}

interface IUniswapV2Callee {
    function uniswapV2Call(address, uint256, uint256, bytes calldata) external;
}
```

### IUniswapV3.sol

```solidity
interface ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata) external returns (uint256);
}

interface INonfungiblePositionManager {
    function mint(MintParams calldata) external returns (uint256, uint128, uint256, uint256);
    function collect(CollectParams calldata) external returns (uint256, uint256);
}

interface IUniswapV3Pool {
    function flash(address, uint256, uint256, bytes calldata) external;
}
```

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testGetActions

# Gas report
forge test --gas-report
```

## Adding New Actions

To add a new action:

1. Add the action function to `AttackHarness.sol`:

```solidity
function myNewAction(address param1, uint16 bps) external {
    // Implementation
}
```

2. Register it in `getActions()`:

```solidity
actions[N] = ActionSpec({
    id: N + 1,
    selector: this.myNewAction.selector,
    argc: 2,
    argKinds: new ArgKind[](2)
});
actions[N].argKinds[0] = ArgKind.Address;
actions[N].argKinds[1] = ArgKind.Bps;
```

3. Update `action_ir.rs` in VERITE-Lab with matching action ID

## Related Projects

- **[VERITE-Lab](https://github.com/shoheigorila/verite-lab)**: Rust fuzzer that uses this harness
- **[ItyFuzz](https://github.com/fuzzland/ityfuzz)**: Base fuzzing framework

## Known Addresses

### Ethereum Mainnet

| Contract | Address |
|----------|---------|
| Uniswap V2 Router | `0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D` |
| Uniswap V2 Factory | `0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f` |
| Uniswap V3 Router | `0xE592427A0AEce92De3Edee1F18E0157C05861564` |
| Uniswap V3 Factory | `0x1F98431c8aD98523631AE4a59f267346ea31F984` |
| WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |
| USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |
| USDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` |

## License

This project is licensed under the MIT License.

## Disclaimer

This harness is intended for security research and defensive auditing purposes only. Users are responsible for ensuring compliance with applicable laws and regulations. Do not use against systems without proper authorization.
