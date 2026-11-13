import 'kibo_client.dart';
import 'vault_secrets.dart';

/// `client.vault.*`. Only [secrets] is composed here today.
class VaultNamespace {
  final VaultSecrets secrets;

  VaultNamespace(KiboClient client) : secrets = VaultSecrets(client);
}
