// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {RebaseToken} from "../src/RebaseToken.sol";
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
    uint256 public arbSepoliaFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

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
    Register.NetworkDetails arbSepoliaNetworkDetails;

    uint32 constant ARB_SEPOLIA_CHAIN_ID = 421614;
    uint32 constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant SEND_VALUE = 1e5;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia");
        arbSepoliaFork = vm.createFork("arbSepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        // made ccipLocalSimulatorFork persistent so it won't be lost when we switch chains
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // deployed rebaseToken and vault on sepolia
        vm.prank(Owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(address(sepoliaToken));
        vm.stopPrank();

        // Switched chain to arbSepolia and then deployed the rebaseToken on arbSepolia also
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(Owner);
        arbSepoliaToken = new RebaseToken();
        vm.stopPrank();

        // Fetched Chain Details from the ccip
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(SEPOLIA_CHAIN_ID);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(ARB_SEPOLIA_CHAIN_ID);

        // Deployed Token Pool on sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)), sepoliaNetworkDetails.rmnProxyAddress, sepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();

        // Deployed Token Pool on arbSepolia
        vm.startPrank(Owner);
        vm.selectFork(arbSepoliaFork);
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();

        // Provided mint and burn rights to vault and tokenPool on sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        vm.stopPrank();

        // Provided mint and burn rights to tokenPool on arbSepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(Owner);
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        vm.stopPrank();

        // Get the Owner registered as the admin and provide rights of the tokens
        // For sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        vm.stopPrank();

        // For arbSepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(Owner);
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        vm.stopPrank();

        // Accepting the admin role
        // For sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        vm.stopPrank();
        // For arbSepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(Owner);
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        vm.stopPrank();

        // Set the token Pool for each token deployed
        // For sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(Owner);
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaPool));
        vm.stopPrank();
        // For arbSepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(Owner);
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaPool));
        vm.stopPrank();

        // Apply the chain updates so that both chains get to interact with each other
        _applyChainUpdates(
            sepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

        _applyChainUpdates(
            arbSepoliaFork,
            address(arbSepoliaPool),
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
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });

        // get the fee
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        // mint the fee link tokens to the sender, to complete transaction
        ccipLocalSimulatorFork.requestLinkFromFaucet(sender, fee);

        // sender approved the router to spend his link tokens(Fee amount)
        vm.startPrank(sender);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        // sender then approved the router to spend his tokens, in order to forward the tokens cross-chain
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        uint256 localBalanceBefore = RebaseToken(localToken).balanceOf(sender);

        // ccip forwards the message
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        // Fetch User balance on local(Source) chain
        uint256 localBalanceAfter = RebaseToken(localToken).balanceOf(sender);

        // Fetch User interest on local(Source) chain
        uint256 localUserInterestRate = RebaseToken(localToken).getUserInterestRate(sender);
        vm.stopPrank();

        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);

        vm.warp(block.timestamp + 20 minutes); // Fast Forward Time

        // Get destination balance before routing
        vm.selectFork(remoteFork);
        uint256 remoteBalanceBefore = RebaseToken(remoteToken).balanceOf(sender);

        // Return to source chain because simulator routes from active chain
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // Now check destination state
        vm.selectFork(remoteFork);
        // // Fetch User balance on Remote(Destination)) chain
        uint256 remoteBalanceAfter = RebaseToken(remoteToken).balanceOf(sender);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);
        // Fetch User Interest on Remote(Destination) chain
        uint256 remoteUserInterestRate = RebaseToken(remoteToken).getUserInterestRate(sender);
        assertEq(localUserInterestRate, remoteUserInterestRate);
    }

    function _applyChainUpdates(
        uint256 forkId,
        address localPoolAddress,
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress
    ) private {
        vm.selectFork(forkId);
        vm.prank(Owner);

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

        RebaseTokenPool(localPoolAddress).applyChainUpdates(new uint64[](0), chainsToAdd);
    }

    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(User, SEND_VALUE);
        vm.prank(User);

        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        assertEq(sepoliaToken.balanceOf(User), SEND_VALUE);

        _bridgeTokens(
            sepoliaFork,
            arbSepoliaFork,
            address(sepoliaToken),
            address(arbSepoliaToken),
            User,
            SEND_VALUE,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails
        );

        vm.selectFork(sepoliaFork);
        console.log(sepoliaToken.hasRole(keccak256("MINT_AND_BURN_ROLE"), address(sepoliaPool)));

        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);

        uint256 amount = arbSepoliaToken.balanceOf(User);
        console.log(arbSepoliaToken.hasRole(keccak256("MINT_AND_BURN_ROLE"), address(arbSepoliaPool)));
        console.log("User Balance: ", amount);

        _bridgeTokens(
            arbSepoliaFork,
            sepoliaFork,
            address(arbSepoliaToken),
            address(sepoliaToken),
            User,
            amount,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails
        );
    }
}
