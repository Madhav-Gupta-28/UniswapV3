// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;


import "./interfaces/IERC20.sol";
import "./UniswapV3Pool.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./lib/LiquidityMath.sol";
import "./lib/TickMath.sol";
import "./interfaces/IUniswapV3Manager.sol";



contract UniswapV3Manager {


    error SlippageCheckFailed(uint256 amount0, uint256 amount1);


    struct MintParams {
        address poolAddress;
        int24 lowerTick;
        int24 upperTick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    function mint(MintParams calldata params) public returns(uint256 amount0 , uint256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(params.poolAddress);

        (uint160 sqrtPriceX96,) = pool.slot0();

        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(params.lowerTick);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(params.upperTick);

        uint128 liquidity = LiquidityMath.getLiquidityForAmounts(sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, params.amount0Desired, params.amount1Desired);

        (amount0,amount1) = pool.mint(msg.sender, params.lowerTick, params.upperTick, liquidity, abi.encode(
            IUniswapV3Pool.CallbackData({
                token0 : pool.token0(),
                token1 : pool.token1(),
                payer:msg.sender
            })
        ));

        if (amount0 <   params.amount0Min || amount1 < params.amount1Min) revert SlippageCheckFailed(amount0,amount1);

    }

    // function swap(address poolAddress_, bytes calldata data) public {
    //     UniswapV3Pool(poolAddress_).swap(msg.sender, data);
    // }
}