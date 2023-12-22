// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./lib/Tick.sol";
import "./lib/Position.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "./lib/TickBitMap.sol";
import "./lib/TickMath.sol";
import "./lib/Math.sol";
import "./lib/SwapMath.sol";
import "./lib/LiquidityMath.sol";

contract UniswapV3Pool {

    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    // using Bitmap for Ticks
    using TickBitmap for mapping(int16 => uint256);
    mapping(int16 => uint256 ) public tickBitmap;


    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    // Here I am packing variable 
    struct Slot0{
        uint160 sqrtPriceX96;
        int24 tick;
    }

    Slot0 public slot0;

    // Struct for Storing Data for Callbacks
    struct CallbackData{
        address token0;
        address token1;
        address payer;
    }

    struct SwapState{
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
    }

    struct StepState{
        uint160 sqrtPriceStartX96;
        int24 nextTick;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        bool initialized;
    }

    uint128 public liquidity; // Keeping track of amount of Liquidity

    // Ticks Info
    mapping(int24 => Tick.Info) public ticks;
    mapping(bytes32 => Position.Info) public positions;

    // Initialzing variables in the constructor
    constructor(address token0_ , address token1_ , uint160  sqrtPriceX96_ , int24 tick_){
        token0  = token0_;
        token1 = token1_;
        slot0 = Slot0(sqrtPriceX96_,tick_);
    }

    // Errors
    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount();
    error InvalidPriceLimit();

    // Events
    event Mint( address sender, address indexed owner, int24 indexed tickLower,int24 indexed tickUpper,uint128 amount,uint256 amount0,uint256 amount1  );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );




    function mint(address owner , int24 lowertick , int24 uppertick , uint128 amount , 
        bytes calldata data) external returns(uint256 amount0 , uint256 amount1){
        if(
            lowertick < MIN_TICK || 
            uppertick > MAX_TICK ||
            lowertick >= uppertick
        ){
            revert InvalidTickRange();
        }

        if(amount <=  0) revert ZeroLiquidity();

        Slot0 memory slot0_ = slot0;

        if (slot0_.tick < lowertick) {
            amount0 = Math.calcAmount0Delta(TickMath.getSqrtRatioAtTick(lowertick), TickMath.getSqrtRatioAtTick(uppertick), amount);     
        }else if (slot0_.tick < uppertick) {
            amount0 = Math.calcAmount0Delta(slot0_.sqrtPriceX96, TickMath.getSqrtRatioAtTick(uppertick), amount);
            liquidity = LiquidityMath.addLiquidity(liquidity, int128(amount));
        }else{
            amount1 = Math.calcAmount0Delta(TickMath.getSqrtRatioAtTick(lowertick), TickMath.getSqrtRatioAtTick(uppertick), amount);
        }



        bool flippedLower = ticks.update(lowertick,amount);
        bool flippedUpper = ticks.update(uppertick,amount);

       if (flippedLower) {
            tickBitmap.flipTick(lowertick, 1);
        }

        if (flippedUpper) {
            tickBitmap.flipTick(uppertick, 1);
        }


        Position.Info storage position = positions.get(owner,lowertick,uppertick);

        position.update(amount);

        liquidity += uint128(amount);

        
        amount0 = Math.calcAmount0Delta(slot0_ .sqrtPriceX96, TickMath.getSqrtRatioAtTick(lowertick), liquidity);
        amount1 = Math.calcAmount0Delta(slot0_ .sqrtPriceX96, TickMath.getSqrtRatioAtTick(uppertick), liquidity);


        uint256 balance0before;
        uint256 balance1before;

        if(amount0 > 0 ) balance0before = balance0() ;
        if(amount1 > 0) balance1before = balance1();

       IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0,amount1,data);



        if (amount0 > 0 && balance0before + amount0 > balance0())
        revert InsufficientInputAmount();
        if (amount1 > 0 && balance1before + amount1 > balance1())
        revert InsufficientInputAmount();

        emit Mint(msg.sender, owner, lowertick, uppertick, amount, amount0, amount1);

    }


    function swap(
        address recipient ,  bool zeroForOne , uint256 amountSpecified  , uint160 sqrtPriceLimitX96 , bytes calldata data
        ) public returns(int256 amount0 , int256 amount1){


        Slot0 memory slot0_ = slot0;  

        if(
           zeroForOne
                ? sqrtPriceLimitX96 > slot0_.sqrtPriceX96 ||
                    sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 < slot0_.sqrtPriceX96 ||
                    sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO
        )  revert InvalidPriceLimit();

        SwapState memory swapstate = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0_.sqrtPriceX96,
            tick: slot0_.tick
        });


        while (swapstate.amountSpecifiedRemaining > 0 && swapstate.sqrtPriceX96 != sqrtPriceLimitX96){
            StepState memory stepstate;

            stepstate.sqrtPriceStartX96 = swapstate.sqrtPriceX96;

            (stepstate.nextTick,stepstate.initialized) = tickBitmap.nextInitializedTickWithinOneWord(swapstate.tick, 1, zeroForOne);
            stepstate.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(stepstate.nextTick);

            (swapstate.sqrtPriceX96,stepstate.amountIn,stepstate.amountOut) = SwapMath.computeSwapStep(swapstate.sqrtPriceX96 ,(
            zeroForOne
                ? stepstate.sqrtPriceNextX96 < sqrtPriceLimitX96
                : stepstate.sqrtPriceNextX96 > sqrtPriceLimitX96
        )
            ? sqrtPriceLimitX96
            : stepstate.sqrtPriceNextX96, liquidity, swapstate.amountSpecifiedRemaining);

            swapstate.amountSpecifiedRemaining -= stepstate.amountIn;
            swapstate.amountCalculated += stepstate.amountOut;
            swapstate.tick = TickMath.getTickAtSqrtRatio(swapstate.sqrtPriceX96);

        }

         if (swapstate.sqrtPriceX96 == stepstate.sqrtPriceNextX96) {
                if (stepstate.initialized) {
                    int128 liquidityDelta = ticks.cross(stepstate.nextTick);

                    if (zeroForOne) liquidityDelta = -liquidityDelta;

                    swapstate.liquidity = LiquidityMath.addLiquidity(
                        swapstate.liquidity,
                        liquidityDelta
                    );

                    if (swapstate.liquidity == 0) revert NotEnoughLiquidity();
                }

                swapstate.tick = zeroForOne ? stepstate.nextTick - 1 : stepstate.nextTick;
            } else if (swapstate.sqrtPriceX96 != stepstate.sqrtPriceStartX96) {
                swapstate.tick = TickMath.getTickAtSqrtRatio(swapstate.sqrtPriceX96);
            }
        };



        if(swapstate.tick != slot0_.tick){
            (slot0.sqrtPriceX96,slot0.tick) = (swapstate.sqrtPriceX96,swapstate.tick);
        }

        (amount0 , amount1) = zeroForOne ? (
            int256(amountSpecified  - swapstate.amountSpecifiedRemaining) , -int256(swapstate.amountCalculated)
        ) : (
            -int256(swapstate.amountCalculated),
             int256(amountSpecified - swapstate.amountSpecifiedRemaining)
        );


        if (zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(-amount1));

            uint256 balance0Before  = balance0();

            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);

            if(balance0Before + uint256(amount0) > balance0()){
                  revert InsufficientInputAmount();
            }
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance1Before + uint256(amount1) > balance1())
                revert InsufficientInputAmount();
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
            slot0.tick
        );

    



    }



    // Helper Functions 
    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }

}
