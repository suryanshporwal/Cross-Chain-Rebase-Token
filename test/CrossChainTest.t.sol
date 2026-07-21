// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/Interfaces/IRebaseToken.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register, Client} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Vault} from "../src/Vault.sol";
import {
    RegistryModuleOwnerCustom
} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";

import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool, RateLimiter} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    address Owner = makeAddr("owner");
    address User = makeAddr("user");
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    Vault public vault;

    uint256 public sepoliaFork;
    uint256 public hoodiFork;

    RebaseToken sepoliaToken;
    RebaseToken hoodiToken;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool hoodiPool;

    // For reference in register
    // struct NetworkDetails {
    //     uint64 chainSelector;
    //     address routerAddress;
    //     address linkAddress;
    //     address wrappedNativeAddress;
    //     address ccipBnMAddress;
    //     address ccipLnMAddress;
    //     address rmnProxyAddress;
    //     address registryModuleOwnerCustomAddress;
    //     address tokenAdminRegistryAddress;
    // }

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails hoodiNetworkDetails;

    uint32 constant HOODI_CHAIN_ID = 560048;
    uint32 constant SEPOLIA_CHAIN_ID = 11155111;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia");
        hoodiFork = vm.createFork("hoodi");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        // made ccipLocalSimulatorFork persistent so it won't be lost when we switch chains
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // deployed rebaseToken and vault on sepolia
        vm.prank(Owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(address(sepoliaToken));
        vm.stopPrank();

        // Switched chain to hoodi and then deployed the rebaseToken on hoodi also
        vm.selectFork(hoodiFork);
        vm.startPrank(Owner);
        hoodiToken = new RebaseToken();
        vm.stopPrank();

        // Fetched Chain Details from the ccip
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(SEPOLIA_CHAIN_ID);
        hoodiNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(HOODI_CHAIN_ID);

        // Deployed Token Pool on sepolia
        vm.selectFork(sepoliaFork);
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)), sepoliaNetworkDetails.rmnProxyAddress, sepoliaNetworkDetails.routerAddress
        );

        // Deployed Token Pool on Hoodi
        vm.selectFork(hoodiFork);
        hoodiPool = new RebaseTokenPool(
            IERC20(address(hoodiToken)), hoodiNetworkDetails.rmnProxyAddress, hoodiNetworkDetails.routerAddress
        );

        // Provided mint and burn rights to vault and tokenPool on sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        vm.stopPrank();

        // Provided mint and burn rights to tokenPool on hoodi
        vm.selectFork(hoodiFork);
        vm.startPrank(Owner);
        hoodiToken.grantMintAndBurnRole(address(hoodiPool));
        vm.stopPrank();

        // Get the Owner registered as the admin and provide rights of the tokens
        // For sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        vm.stopPrank();

        // For hoodi
        vm.selectFork(hoodiFork);
        vm.startPrank(Owner);
        RegistryModuleOwnerCustom(hoodiNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(hoodiToken));
        vm.stopPrank();

        // Accepting the admin role
        // For sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        vm.stopPrank();
        // For Hoodi
        vm.selectFork(hoodiFork);
        vm.startPrank(Owner);
        TokenAdminRegistry(hoodiNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(hoodiToken));
        vm.stopPrank();

        // Set the token Pool for each token deployed
        // For sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaPool));
        vm.stopPrank();
        // For Hoodi
        vm.selectFork(hoodiFork);
        vm.startPrank(Owner);
        TokenAdminRegistry(hoodiNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(hoodiToken), address(hoodiPool));
        vm.stopPrank();

        _applyChainUpdates(
            sepoliaFork,
            address(sepoliaPool),
            hoodiNetworkDetails.chainSelector,
            address(hoodiPool),
            address(hoodiToken)
        );

        _applyChainUpdates(
            hoodiFork,
            address(hoodiPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
        // Done
    }

    function _bridgeTokens(
        uint256 localFork,
        uint256 remoteFork,
        address localToken,
        address remoteToken,
        address sender,
        uint256 amountToBridge,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        // On localFork pranking as user
        vm.selectFork(localFork);
        // Initialize the token amounts array
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        // Construct the EVM2AnyMessage
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(sender), // receiver on destination chain
            data: "", // No additional data payload
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });

        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        ccipLocalSimulatorFork.requestLinkFromFaucet(sender, fee);

        vm.startPrank(sender);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        uint256 localBalanceBefore = RebaseToken(localToken).balanceOf(sender);

        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        uint256 localBalanceAfter = RebaseToken(localToken).balanceOf(sender);
        vm.stopPrank();
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);

        vm.warp(block.timestamp + 20 minutes); // Fast Forward Time

        // Fetched balance on remoteFork for the rebaseToken
        vm.selectFork(remoteFork);
        uint256 remoteBalanceBefore = RebaseToken(remoteToken).balanceOf(sender);

        // Return to source chain
        vm.selectFork(localFork);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        vm.selectFork(remoteFork); // More explicit
        uint256 remoteBalanceAfter = RebaseToken(remoteToken).balanceOf(sender);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);
    }

    function _applyChainUpdates(
        uint256 forkId,
        address localPoolAddress,
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress
    ) private {
        vm.selectFork(forkId);

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePoolAddress);

        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        vm.prank(Owner);
        RebaseTokenPool(localPoolAddress).applyChainUpdates(new uint64[](0), chainsToAdd);
    }
}
