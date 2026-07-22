// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {RebaseToken} from "./RebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    uint8 constant DEFAULT_DECIMALS = 18;
    address constant DISABLE_ADVANCE_POOL_HOOKS = address(0); // Hooks not supported

    constructor(IERC20 _token, address _rmnProxy, address _router)
        TokenPool(_token, DEFAULT_DECIMALS, DISABLE_ADVANCE_POOL_HOOKS, _rmnProxy, _router)
    {}

    function _lockOrBurn(uint64, uint256 amount) internal override {
        RebaseToken(address(getToken())).burn(address(this), amount);
    }

    function _releaseOrMint(address receiver, uint256 amount, uint64) internal override {
        RebaseToken(address(getToken())).mint(receiver, amount);
    }
}
