// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2.sol";
import "./interfaces/IUniswapV3.sol";
import "./interfaces/IWETH.sol";

/// @title VERITE Attack Harness
/// @notice Centralized contract for executing DeFi actions during fuzzing
/// @dev All actions are designed to be called with percentage-based amounts (Bps)
contract AttackHarness is IUniswapV2Callee, IUniswapV3FlashCallback {
    // ============ Constants ============

    uint16 public constant BPS_MAX = 10000;

    // ============ State ============

    address public owner;
    bool private _locked;

    // Flash loan state
    address private _flashLoanToken;
    uint256 private _flashLoanAmount;
    bytes private _flashLoanData;

    // ============ Structs ============

    /// @notice Action specification for registry
    struct ActionSpec {
        uint32 id;
        bytes4 selector;
        uint8 argc;
        uint8[] argKinds; // 0=U256, 1=Bps, 2=Token, 3=Address, 4=Bool, 5=Int24
    }

    // ============ Events ============

    event ActionExecuted(uint32 indexed actionId, bool success);
    event ProfitRecorded(address token, int256 amount);

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "Reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    // ============ Constructor ============

    constructor() {
        owner = msg.sender;
    }

    // ============ Action Registry ============

    /// @notice Get all available actions
    /// @return specs Array of action specifications
    function getActions() external pure returns (ActionSpec[] memory specs) {
        specs = new ActionSpec[](11);

        // A1: erc20TransferBps(token, to, bps)
        uint8[] memory args1 = new uint8[](3);
        args1[0] = 2; args1[1] = 3; args1[2] = 1;
        specs[0] = ActionSpec(1, this.erc20TransferBps.selector, 3, args1);

        // A2: v2SwapExactInBps(router, tokenIn, tokenOut, bps, minOutBps)
        uint8[] memory args2 = new uint8[](5);
        args2[0] = 3; args2[1] = 2; args2[2] = 2; args2[3] = 1; args2[4] = 1;
        specs[1] = ActionSpec(2, this.v2SwapExactInBps.selector, 5, args2);

        // A3: v2AddLiqBps(router, token0, token1, bps0, bps1)
        uint8[] memory args3 = new uint8[](5);
        args3[0] = 3; args3[1] = 2; args3[2] = 2; args3[3] = 1; args3[4] = 1;
        specs[2] = ActionSpec(3, this.v2AddLiqBps.selector, 5, args3);

        // A4: v2RemoveLiqBps(router, lpToken, bps)
        uint8[] memory args4 = new uint8[](3);
        args4[0] = 3; args4[1] = 2; args4[2] = 1;
        specs[3] = ActionSpec(4, this.v2RemoveLiqBps.selector, 3, args4);

        // A5: flashloanV2(pair, token, amountBps)
        uint8[] memory args5 = new uint8[](3);
        args5[0] = 3; args5[1] = 2; args5[2] = 1;
        specs[4] = ActionSpec(5, this.flashloanV2.selector, 3, args5);

        // A6: v3SwapExactIn(router, tokenIn, tokenOut, fee, bps, sqrtPriceLimitX96)
        uint8[] memory args6 = new uint8[](6);
        args6[0] = 3; args6[1] = 2; args6[2] = 2; args6[3] = 0; args6[4] = 1; args6[5] = 0;
        specs[5] = ActionSpec(6, this.v3SwapExactIn.selector, 6, args6);

        // A7: v3MintPosition(nftManager, token0, token1, fee, tickLower, tickUpper, bps0, bps1)
        uint8[] memory args7 = new uint8[](8);
        args7[0] = 3; args7[1] = 2; args7[2] = 2; args7[3] = 0;
        args7[4] = 5; args7[5] = 5; args7[6] = 1; args7[7] = 1;
        specs[6] = ActionSpec(7, this.v3MintPosition.selector, 8, args7);

        // A8: v3CollectFees(nftManager, tokenId)
        uint8[] memory args8 = new uint8[](2);
        args8[0] = 3; args8[1] = 0;
        specs[7] = ActionSpec(8, this.v3CollectFees.selector, 2, args8);

        // A9: approveToken(token, spender, amount)
        uint8[] memory args9 = new uint8[](3);
        args9[0] = 2; args9[1] = 3; args9[2] = 0;
        specs[8] = ActionSpec(9, this.approveToken.selector, 3, args9);

        // A10: wrapEth(weth, amount)
        uint8[] memory args10 = new uint8[](2);
        args10[0] = 3; args10[1] = 0;
        specs[9] = ActionSpec(10, this.wrapEth.selector, 2, args10);

        // A11: unwrapEth(weth, amount)
        uint8[] memory args11 = new uint8[](2);
        args11[0] = 3; args11[1] = 0;
        specs[10] = ActionSpec(11, this.unwrapEth.selector, 2, args11);
    }

    // ============ A1: ERC20 Transfer ============

    /// @notice Transfer ERC20 tokens by percentage of balance
    /// @param token Token address
    /// @param to Recipient address
    /// @param bps Percentage in basis points (0-10000)
    function erc20TransferBps(address token, address to, uint16 bps) external onlyOwner {
        require(bps <= BPS_MAX, "Invalid bps");
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 amount = (balance * bps) / BPS_MAX;
        if (amount > 0) {
            require(IERC20(token).transfer(to, amount), "Transfer failed");
        }
        emit ActionExecuted(1, true);
    }

    // ============ A2: Uniswap V2 Swap ============

    /// @notice Swap exact input on Uniswap V2
    /// @param router Router address
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param bps Percentage of tokenIn balance to swap
    /// @param minOutBps Minimum output as percentage of expected (slippage protection)
    function v2SwapExactInBps(
        address router,
        address tokenIn,
        address tokenOut,
        uint16 bps,
        uint16 minOutBps
    ) external onlyOwner nonReentrant {
        require(bps <= BPS_MAX && minOutBps <= BPS_MAX, "Invalid bps");

        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        uint256 amountIn = (balance * bps) / BPS_MAX;

        if (amountIn == 0) {
            emit ActionExecuted(2, false);
            return;
        }

        IERC20(tokenIn).approve(router, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amountsOut = IUniswapV2Router02(router).getAmountsOut(amountIn, path);
        uint256 amountOutMin = (amountsOut[1] * minOutBps) / BPS_MAX;

        IUniswapV2Router02(router).swapExactTokensForTokens(
            amountIn, amountOutMin, path, address(this), block.timestamp + 1
        );

        emit ActionExecuted(2, true);
    }

    // ============ A3: Uniswap V2 Add Liquidity ============

    /// @notice Add liquidity on Uniswap V2
    /// @param router Router address
    /// @param token0 First token
    /// @param token1 Second token
    /// @param bps0 Percentage of token0 balance
    /// @param bps1 Percentage of token1 balance
    function v2AddLiqBps(
        address router,
        address token0,
        address token1,
        uint16 bps0,
        uint16 bps1
    ) external onlyOwner nonReentrant {
        require(bps0 <= BPS_MAX && bps1 <= BPS_MAX, "Invalid bps");

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = (balance0 * bps0) / BPS_MAX;
        uint256 amount1 = (balance1 * bps1) / BPS_MAX;

        if (amount0 == 0 || amount1 == 0) {
            emit ActionExecuted(3, false);
            return;
        }

        IERC20(token0).approve(router, amount0);
        IERC20(token1).approve(router, amount1);

        IUniswapV2Router02(router).addLiquidity(
            token0, token1, amount0, amount1, 0, 0, address(this), block.timestamp + 1
        );

        emit ActionExecuted(3, true);
    }

    // ============ A4: Uniswap V2 Remove Liquidity ============

    /// @notice Remove liquidity from Uniswap V2
    /// @param router Router address
    /// @param lpToken LP token address
    /// @param bps Percentage of LP tokens to remove
    function v2RemoveLiqBps(address router, address lpToken, uint16 bps) external onlyOwner nonReentrant {
        require(bps <= BPS_MAX, "Invalid bps");

        uint256 balance = IERC20(lpToken).balanceOf(address(this));
        uint256 liquidity = (balance * bps) / BPS_MAX;

        if (liquidity == 0) {
            emit ActionExecuted(4, false);
            return;
        }

        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();

        IERC20(lpToken).approve(router, liquidity);

        IUniswapV2Router02(router).removeLiquidity(
            token0, token1, liquidity, 0, 0, address(this), block.timestamp + 1
        );

        emit ActionExecuted(4, true);
    }

    // ============ A5: Uniswap V2 Flash Loan ============

    /// @notice Take flash loan from Uniswap V2 pair
    /// @param pair Pair address
    /// @param token Token to borrow
    /// @param amountBps Amount as percentage of pair's reserve
    function flashloanV2(address pair, address token, uint16 amountBps) external onlyOwner nonReentrant {
        require(amountBps <= BPS_MAX, "Invalid bps");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();

        uint256 amount;
        uint256 amount0Out;
        uint256 amount1Out;

        if (token == token0) {
            amount = (uint256(reserve0) * amountBps) / BPS_MAX;
            amount0Out = amount;
        } else if (token == token1) {
            amount = (uint256(reserve1) * amountBps) / BPS_MAX;
            amount1Out = amount;
        } else {
            revert("Invalid token");
        }

        if (amount == 0) {
            emit ActionExecuted(5, false);
            return;
        }

        _flashLoanToken = token;
        _flashLoanAmount = amount;

        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(token, amount));

        emit ActionExecuted(5, true);
    }

    /// @notice Uniswap V2 flash loan callback
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(sender == address(this), "Invalid sender");

        (address token, uint256 amount) = abi.decode(data, (address, uint256));

        // Calculate repayment with 0.3% fee
        uint256 repayment = amount + ((amount * 3) / 997) + 1;

        // Transfer repayment
        require(IERC20(token).transfer(msg.sender, repayment), "Repayment failed");
    }

    // ============ A6: Uniswap V3 Swap ============

    /// @notice Swap exact input on Uniswap V3
    /// @param router Router address
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param fee Pool fee tier
    /// @param bps Percentage of tokenIn balance
    /// @param sqrtPriceLimitX96 Price limit (0 for no limit)
    function v3SwapExactIn(
        address router,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint16 bps,
        uint160 sqrtPriceLimitX96
    ) external onlyOwner nonReentrant {
        require(bps <= BPS_MAX, "Invalid bps");

        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        uint256 amountIn = (balance * bps) / BPS_MAX;

        if (amountIn == 0) {
            emit ActionExecuted(6, false);
            return;
        }

        IERC20(tokenIn).approve(router, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        ISwapRouter(router).exactInputSingle(params);

        emit ActionExecuted(6, true);
    }

    // ============ A7: Uniswap V3 Mint Position ============

    /// @notice Mint Uniswap V3 liquidity position
    /// @param nftManager Position manager address
    /// @param token0 First token
    /// @param token1 Second token
    /// @param fee Pool fee tier
    /// @param tickLower Lower tick
    /// @param tickUpper Upper tick
    /// @param bps0 Percentage of token0 balance
    /// @param bps1 Percentage of token1 balance
    function v3MintPosition(
        address nftManager,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint16 bps0,
        uint16 bps1
    ) external onlyOwner nonReentrant {
        require(bps0 <= BPS_MAX && bps1 <= BPS_MAX, "Invalid bps");

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = (balance0 * bps0) / BPS_MAX;
        uint256 amount1 = (balance1 * bps1) / BPS_MAX;

        if (amount0 == 0 && amount1 == 0) {
            emit ActionExecuted(7, false);
            return;
        }

        IERC20(token0).approve(nftManager, amount0);
        IERC20(token1).approve(nftManager, amount1);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 1
        });

        INonfungiblePositionManager(nftManager).mint(params);

        emit ActionExecuted(7, true);
    }

    // ============ A8: Uniswap V3 Collect Fees ============

    /// @notice Collect fees from V3 position
    /// @param nftManager Position manager address
    /// @param tokenId Position NFT ID
    function v3CollectFees(address nftManager, uint256 tokenId) external onlyOwner {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        INonfungiblePositionManager(nftManager).collect(params);

        emit ActionExecuted(8, true);
    }

    // ============ A9: Approve Token ============

    /// @notice Approve token spending
    /// @param token Token address
    /// @param spender Spender address
    /// @param amount Amount to approve
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
        IERC20(token).approve(spender, amount);
        emit ActionExecuted(9, true);
    }

    // ============ A10: Wrap ETH ============

    /// @notice Wrap ETH to WETH
    /// @param weth WETH address
    /// @param amount Amount to wrap
    function wrapEth(address weth, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient ETH");
        IWETH(weth).deposit{value: amount}();
        emit ActionExecuted(10, true);
    }

    // ============ A11: Unwrap ETH ============

    /// @notice Unwrap WETH to ETH
    /// @param weth WETH address
    /// @param amount Amount to unwrap
    function unwrapEth(address weth, uint256 amount) external onlyOwner {
        IWETH(weth).withdraw(amount);
        emit ActionExecuted(11, true);
    }

    // ============ V3 Flash Callback ============

    /// @notice Uniswap V3 flash callback
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override {
        // Implement flash loan logic here
    }

    // ============ Helper Functions ============

    /// @notice Get balance of token
    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Withdraw tokens (emergency)
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    /// @notice Withdraw ETH (emergency)
    function withdrawEth(uint256 amount) external onlyOwner {
        payable(owner).transfer(amount);
    }

    /// @notice Receive ETH
    receive() external payable {}
}
