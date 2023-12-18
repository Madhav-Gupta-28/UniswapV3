// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.14;


library Position {
    struct Info {
        uint128 liquidity;
    }

    function update(Info storage self , uint128 liquidityDelta) internal {
        uint128 liquidityBefore = self.liquidity;
        uint128 liquidityAfter  = liquidityBefore + liquidityDelta;

        self.liquidity = liquidityAfter;
    }


    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 lowertick,
        int24 uppertick
    ) internal view returns(Position.Info storage position){
        position = self[keccak256(abi.encodePacked(owner , lowertick , uppertick))]; // we pack 3 keys here for mapping so it only takes 32 bytes instead of 96 bytes
        

    }
}