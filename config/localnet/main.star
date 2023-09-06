eth_network_module = import_module(
    "github.com/kurtosis-tech/eth-network-package/main.star"
)
prelaunch_data_generator_launcher = import_module(
    "github.com/kurtosis-tech/eth-network-package/src/prelaunch_data_generator/prelaunch_data_generator_launcher/prelaunch_data_generator_launcher.star"
)
shared_utils = import_module(
    "github.com/kurtosis-tech/eth-network-package/shared_utils/shared_utils.star"
)
keystore_files_module = import_module(
    "github.com/kurtosis-tech/eth-network-package/src/prelaunch_data_generator/cl_validator_keystores/keystore_files.star"
)
keystores_result = import_module(
    "github.com/kurtosis-tech/eth-network-package/src/prelaunch_data_generator/cl_validator_keystores/generate_keystores_result.star"
)


KEYSTORES_OUTPUT_DIRPATH = "/justfarming-keystore"
KEYSTORES_GENERATION_TOOL_NAME = "eth2-val-tools"

SUCCESSFUL_EXEC_CMD_EXIT_CODE = 0

RAW_KEYS_DIRNAME = "keys"
RAW_SECRETS_DIRNAME = "secrets"
NIMBUS_KEYS_DIRNAME = "nimbus-keys"
PRYSM_DIRNAME = "prysm"
TEKU_KEYS_DIRNAME = "teku-keys"
TEKU_SECRETS_DIRNAME = "teku-secrets"


def generate_justfarming_keystore(plan, mnemonic, num_validators, capella_fork_epoch):
    service_name = prelaunch_data_generator_launcher.launch_prelaunch_data_generator(
        plan,
        {},
        "jf-genesis-data",
        capella_fork_epoch
    )

    start_index = 0
    stop_index = num_validators

    command_str = '{0} keystores --insecure --out-loc {1} --source-mnemonic "{2}" --source-min {3} --source-max {4}'.format(
        KEYSTORES_GENERATION_TOOL_NAME,
        KEYSTORES_OUTPUT_DIRPATH,
        mnemonic,
        start_index,
        stop_index,
    )

    command_result = plan.exec(
        recipe=ExecRecipe(command=["sh", "-c", command_str]), service_name=service_name
    )
    plan.assert(command_result["code"], "==", SUCCESSFUL_EXEC_CMD_EXIT_CODE)

    # Store outputs into files artifacts
    artifact_name = plan.store_service_files(
        service_name, KEYSTORES_OUTPUT_DIRPATH, name="justfarming-keystore"
    )

    # This is necessary because the way Kurtosis currently implements artifact-storing is
    base_dirname_in_artifact = shared_utils.path_base(KEYSTORES_OUTPUT_DIRPATH)
    keystore_files = keystore_files_module.new_keystore_files(
        artifact_name,
        shared_utils.path_join(base_dirname_in_artifact, RAW_KEYS_DIRNAME),
        shared_utils.path_join(base_dirname_in_artifact, RAW_SECRETS_DIRNAME),
        shared_utils.path_join(base_dirname_in_artifact, NIMBUS_KEYS_DIRNAME),
        shared_utils.path_join(base_dirname_in_artifact, PRYSM_DIRNAME),
        shared_utils.path_join(base_dirname_in_artifact, TEKU_KEYS_DIRNAME),
        shared_utils.path_join(base_dirname_in_artifact, TEKU_SECRETS_DIRNAME),
    )

    # we cleanup as the data generation is done
    plan.remove_service(service_name)


def deploy_lighthouse(plan, validator_params):
    generate_justfarming_keystore(
        plan, validator_params["mnemonic"], validator_params["num_validators"], validator_params["capella_fork_epoch"]
    )
    plan.add_service(
        name="justfarming-lighthouse-validator",
        config=ServiceConfig(
            image="sigp/lighthouse:v4.4.1",
            ports={
                "http": PortSpec(
                    number=5042,
                    transport_protocol="TCP",
                    application_protocol="",
                    wait=None,
                ),
                "metrics": PortSpec(
                    number=5064, transport_protocol="TCP", application_protocol="http"
                ),
            },
            files={
                "/genesis": "cl-genesis-data",
                "/validator-keys": "justfarming-keystore",
            },
            cmd=[
                "lighthouse",
                "validator_client",
                "--debug-level=info",
                "--testnet-dir=/genesis/output",
                "--validators-dir=/validator-keys/justfarming-keystore/keys",
                "--secrets-dir=/validator-keys/justfarming-keystore/secrets",
                "--init-slashing-protection",
                "--http",
                "--unencrypted-http-transport",
                "--http-address=0.0.0.0",
                "--http-port=5042",
                "--beacon-nodes=http://cl-1-lighthouse-geth:4000",
                "--suggested-fee-recipient=0x0000000000000000000000000000000000000000",
                "--metrics",
                "--metrics-address=0.0.0.0",
                "--metrics-allow-origin=*",
                "--metrics-port=5064",
            ],
            env_vars={"RUST_BACKTRACE": "full"},
        ),
    )


def run(plan, args):
    plan.print("Spinning up the Ethereum Network")
    network_params = args["network"]
    validator_params = args["validator"]
    plan.print(network_params)
    plan.print(validator_params)
    eth_network_participants, cl_genesis_timestamp, genesis_validators_root = eth_network_module.run(
        plan, network_params
    )
    plan.print("Launching an additional client pair")
    plan.print(plan)
    deploy_lighthouse(plan, validator_params)
