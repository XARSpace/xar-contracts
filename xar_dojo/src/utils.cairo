use starknet::ContractAddress;
use integer::u256_from_felt252;
use ecdsa::check_ecdsa_signature;
use starknet::contract_address_to_felt252;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo_ars::models::{LastCheck, LastBuildId, BuildData};
use dojo_ars::world_config::{VoxelIdV1, AssetContract};
use starknet::get_caller_address;

#[starknet::interface]
trait ICalleeVoxel20<TContractState> {
    fn mint(
        ref self: TContractState,
        to: ContractAddress,
        amount: u256,
    );

    fn burn(
        ref self: TContractState,
        from: ContractAddress,
        amount: u256,
    );
}

#[starknet::interface]
trait ICalleeVoxel1155<TContractState> {
    fn mint(
        ref self: TContractState,
        to: ContractAddress,
        id: u256,
        amount: u256,
    );

    fn burn_batch(
        ref self: TContractState,
        from: ContractAddress,
        ids: Array<u256>,
        amounts: Array<u256>
    );
}

#[starknet::interface]
trait ICalleeCore1155<TContractState> {
    fn mint(
        ref self: TContractState,
        to: ContractAddress,
        id: u256,
        amount: u256,
    );

    fn mint_new(
        ref self: TContractState,
        from: ContractAddress,
        from_id: u256,
        amount: u256,
        fts: Array<FTSpec>,
        shape: Array<PackedShapeItem>,
    ) -> u256;

    fn get_costdata(
        self: @TContractState,
        token_id: u256,
    ) -> CoreCostData;

    fn burn(
        ref self: TContractState,
        from: ContractAddress,
        token_id: u256,
        amount: u256,
    );
}

#[starknet::interface]
trait ICalleeBlueprint<TContractState> {
    fn get_costdata(
        self: @TContractState,
        token_id: u256,
    ) -> CostData;
}

#[starknet::interface]
trait ICalleeBuild<TContractState> {
    fn mint(
        ref self: TContractState, 
        recipient: ContractAddress,
    );
}

#[derive(Drop, Serde)]
struct PackedShapeItem {
    color: felt252,
    material: u64,
    x_y_z: felt252,
}

#[derive(Drop, Serde)]
struct FTSpec {
    token_id: felt252,
    qty: u128,
}

#[derive(Drop, Serde)]
struct CostData {
    base_block: u256,
    color_r: u256,
    color_g: u256,
    color_b: u256,
}

#[derive(Drop, Serde)]
struct CoreCostData {
    base_block: u256,
    color_r: u256,
    color_g: u256,
    color_b: u256,
    core_id: u256,
}


#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    AssetContractEvent: AssetContractEvent,
    InventionLog: InventionLog,
}

#[derive(Drop, starknet::Event)]
struct AssetContractEvent {
    ckey: u256,
    ctype: felt252,
    address: ContractAddress,
    debuga: felt252,
}

#[derive(Drop, starknet::Event)]
struct InventionLog {
    sid: felt252,
    address: ContractAddress,
}

fn verifySign(
    last_check: u256,
    public_key: felt252,
    issuer: felt252,
    receiver: ContractAddress,
    tid: felt252,
    starkid: felt252,
    endid: felt252,
    amt: felt252,
    t721id: felt252,
    remove_block: felt252,
    r: felt252,
    s: felt252
) -> felt252 {
    let tokenid = u256_from_felt252(tid);
    let thischecksid = u256_from_felt252(starkid);
    assert(last_check + 1 == thischecksid, 'CHECKS ID NOT VALID');
    let message_hash = pedersen::pedersen(pedersen::pedersen(pedersen::pedersen(pedersen::pedersen(pedersen::pedersen(pedersen::pedersen(pedersen::pedersen(issuer, contract_address_to_felt252(receiver)), tid), starkid), endid), amt), t721id), remove_block);
    assert(
        check_ecdsa_signature(
            message_hash: message_hash,
            public_key: public_key,
            signature_r: r,
            signature_s: s,
        ),
        'INVALID_SIGNATURE',
    );
    starknet::VALIDATED
}

fn util_mint_voxel_by_checks_v1(
    world: IWorldDispatcher,
    public_key: felt252,
    issuer: felt252,
    receiver: ContractAddress,
    tid: Array<felt252>,
    startid: Array<felt252>,
    endid: Array<felt252>,
    amt: Array<felt252>,
    t721id: Array<felt252>,
    remove_block: Array<felt252>,
    r: Array<felt252>,
    s: Array<felt252>,
) {
    let mut i: usize = 0;

    let _tid = tid.clone();
    let _startid = startid.clone();
    let _endid = endid.clone();
    let _amt = amt.clone();
    let _r = r.clone();
    let _s = s.clone();
    let _t721id = t721id.clone();
    let _rblock = remove_block.clone();
    loop {
        if i == tid.len() {
            break;
        }
        let tokenid = u256_from_felt252(*_tid.at(i));
        let last_check = get!(world, (receiver, tokenid), (LastCheck));
        assert(verifySign(last_check.last_id, public_key, issuer, receiver, *_tid.at(i), *_startid.at(i), *_endid.at(i), *_amt.at(i), *_t721id.at(i), *_rblock.at(i), *_r.at(i), *_s.at(i)) == starknet::VALIDATED, 'valid failed');

        let endchecksid = u256_from_felt252(*_endid.at(i));
        let amount = u256_from_felt252(*_amt.at(i));

        let acontract_address = get!(world, (tokenid), (AssetContract));
        emit !(world, AssetContractEvent{ckey: acontract_address.contract_key, ctype: acontract_address.contract_type, address: acontract_address.contract_address, debuga: 1});
        if acontract_address.contract_type == 20 {
            ICalleeVoxel20Dispatcher { contract_address: acontract_address.contract_address }.mint(receiver, amount * acontract_address.contract_rate);
        } else if acontract_address.contract_type == 1155 {
            ICalleeCore1155Dispatcher { contract_address: acontract_address.contract_address }.mint(receiver, tokenid, amount);
        }
        
        set!(world, (LastCheck { player: receiver, token_id: tokenid, last_id: endchecksid } ));
        i += 1;
    };
}

fn util_mint_build_v1(
    world: IWorldDispatcher,
    from_contract: ContractAddress,
    from_tid: u256,
) {
    let receiver = get_caller_address();
    let config_id: u8 = 1;
    let voxel_ids = get!(world, (config_id), (VoxelIdV1));
    let costdata: CostData = ICalleeBlueprintDispatcher { contract_address: from_contract }.get_costdata(from_tid);
    
    let asset_contract1 = get!(world, (voxel_ids.base_voxel_id), (AssetContract));
    ICalleeVoxel20Dispatcher { contract_address: asset_contract1.contract_address }.burn(receiver, costdata.base_block);
    
    let last_build = get!(world, (receiver), (LastBuildId));
    let new_build_id = last_build.last_id + 1;
    set!(world, (LastBuildId { player: receiver, last_id: new_build_id } ));
    set!(world, (BuildData { player: receiver, build_id: new_build_id, contract_address:from_contract, from_id: from_tid, build_type: 1 } ));
}

fn create_build_from_invention(
    world: IWorldDispatcher,
    public_key: felt252,
    issuer: felt252,
    sid: felt252,
    voxel_num: felt252,
    r: felt252,
    s: felt252,
) {
    assert(verify_invention(public_key, issuer, sid, voxel_num, r, s) == starknet::VALIDATED, 'valid failed');
    let config_id: u8 = 1;
    let voxel_ids = get!(world, (config_id), (VoxelIdV1));
    
    let asset_contract1 = get!(world, (voxel_ids.base_voxel_id), (AssetContract));
    ICalleeVoxel20Dispatcher { contract_address: asset_contract1.contract_address }.burn(get_caller_address(), u256_from_felt252(voxel_num));
    
    emit !(world, InventionLog{sid: sid, address: get_caller_address()});
}

fn verify_invention(
    issuer_public_key: felt252,
    issuer: felt252,
    sid: felt252,
    voxel_num: felt252,
    r: felt252,
    s: felt252
) -> felt252 {
    let caller = get_caller_address();
    let message_hash = pedersen::pedersen(pedersen::pedersen(pedersen::pedersen(issuer, sid), voxel_num), contract_address_to_felt252(caller));
    assert(
        check_ecdsa_signature(
            message_hash: message_hash,
            public_key: issuer_public_key,
            signature_r: r,
            signature_s: s,
        ),
        'invention INVALID_SIGNATURE',
    );
    starknet::VALIDATED
}

fn debug_init_checks(
    world: IWorldDispatcher,
    receiver: ContractAddress,
    tid: Array<felt252>,
) {
    let mut i: usize = 0;

    let _tid = tid.clone();
    loop {
        if i == tid.len() {
            break;
        }
        let tokenid = u256_from_felt252(*_tid.at(i));
        
        set!(world, (LastCheck { player: receiver, token_id: tokenid, last_id: 0 } ));
        i += 1;
    };
}
