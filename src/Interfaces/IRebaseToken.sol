// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRebaseToken {
    function mint(address _to, uint256 amount,uint256 interestRate) external;
    function burn(address _from, uint256 amount) external;
    function balanceOf(address _user) external view returns (uint256);
    function grantMintAndBurnRole(address _account) external;
    function getUserInterestRate(address _account) external view returns (uint256);
    function getInterestRate() external view returns (uint256);
}

