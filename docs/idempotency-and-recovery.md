> Classifier agora é síncrono e sem banco: não reaproveita classificações
> persistidas. As garantias de replay e reuso descritas abaixo aplicam-se ao OCR
> e facematch. A tabela histórica de cache fica preservada, sem uso.

# Idempotência, compensação e recuperação

Este checkpoint mantém PostgreSQL, Oban e uploads locais. Não acrescenta broker,
serviço de saga nem storage remoto. A coordenação combina transações de banco,
compensação de efeitos no filesystem e reconciliação periódica.

## Garantias e limites

| Situação | Comportamento |
| --- | --- |
| Upload ou criação do recurso falha | Rollback de blobs, recurso, imagens, vínculo da chave e job; compensação dos arquivos novos |
| Arquivo já pertence a outro recurso | Preservado; a compensação nunca apaga bytes adotados ou compartilhados |
| Processo morre antes de concluir | PostgreSQL desfaz a transação; inventário local encontra os bytes e temporários abandonados |
| Exclusão do arquivo falha | O registro do blob permanece para permitir retry |
| Blob ainda referenciado | Exclusão recusada antes de tocar no arquivo |
| Mesmo conteúdo chega simultaneamente | Serialização por identidade no banco; um recurso em andamento e um job inicial |
| Mesmo estágio OCR é entregue novamente | Artefato/resultado e próximo job são persistidos juntos, uma única vez por estágio/execução |
| Processamento esgota tentativas | Recurso fica `failed`, com seus vínculos preservados; não é um registro órfão |

Filesystem e PostgreSQL **não têm uma transação distribuída**. Em falhas normais,
a compensação ocorre ao retornar da transação. Em crash, exceção ou indisponibilidade
do banco/storage, a recuperação é eventual e exige que os serviços voltem a funcionar.

Chamadas externas ao engine continuam sujeitas a execução pelo menos uma vez:
uma queda depois de executar o engine e antes de persistir pode exigir nova chamada.
O banco não duplica os efeitos já confirmados. No OCR, duas entregas concorrentes
podem calcular o estágio antes de uma delas confirmar; somente a primeira persiste
o artefato e agenda o próximo job. Não mantemos o documento bloqueado durante o
engine, preservando cancelamento e reprocessamento concorrentes.

## Chaves de requisição e hash do conteúdo

`POST /v1/extractions` e `POST /v1/facematch` aceitam `idempotency-key`
opcional, de 1 a 256 bytes. A chave é vinculada à empresa autenticada, ao serviço,
à identidade do payload e ao recurso criado/reutilizado.

- Mesma chave e payload equivalente retornam o mesmo recurso, com seu estado atual.
- Mesma chave com conteúdo, lados/papéis ou campos relevantes diferentes retorna
  `409 {"code":"idempotency_conflict","detail":"This idempotency key is already bound to a different request."}`, sem deixar outro recurso ou arquivo.
- Chaves diferentes podem apontar ao mesmo recurso reutilizado; cada vínculo
  continua protegido contra mudança posterior de payload.
- Vínculos possuem FKs e são removidos junto com o recurso.
- Uma chave vinculada a um recurso que falhou continua retornando esse recurso;
  use outra chave para uma nova tentativa, ou o reprocessamento explícito do OCR.

SHA-256 e versão do processamento continuam determinando reutilização por conteúdo,
separada da chave da requisição. OCR e facematch reutilizam recursos `pending`/
`processing` com `202`, sem criar outro job, e resultados concluídos com `200`.
Uma consulta idempotente a uma falha terminal retorna `200` com estado `failed`;
isso não transforma falhas técnicas em cache de resultados válidos.

O classifier não participa dessa persistência. Requisições iguais, inclusive
simultâneas, executam classificações independentes; não há cache ou serialização
via banco.

Chaves antigas armazenadas no documento são comparadas antes de criar o novo
vínculo. Quando o registro legado não permite confirmar a identidade dos bytes,
a requisição falha com conflito; não é reinterpretada silenciosamente.

## Fronteira da transação

1. A ingestão obtém locks por SHA-256 em ordem estável e identifica arquivos novos.
2. Persiste bytes e metadados, cria/reutiliza o recurso e vincula a chave.
3. O job inicial entra na mesma transação do recurso.
4. Um erro desfaz o banco. A compensação verifica novamente a propriedade dos
   arquivos antes de excluir; outro pedido pode já ter adotado esses bytes.

Arquivos já existentes e compartilhados não são removidos como compensação.
A exclusão normal verifica referências e usa o banco para impedir uma nova
referência concorrente antes de tocar no storage.

## Reconciliação local

`DocumentOcr.Workers.ReconcileStorage` e `Biometrics.Workers.Reconcile` rodam
a cada cinco minutos. A carência padrão é de uma hora.

- Metadados sem referências são removidos em lotes de até 100 por execução.
- O inventário verifica os arquivos regulares reconhecidos em `kyc_documents/`.
- Objetos sem registro/vínculo e temporários de escrita abandonados são removidos.
- Arquivos recentes, referenciados ou em uma gravação protegida por lock são preservados.
- Falhas permitem retry do worker; a próxima varredura também reencontra os objetos.

O inventário físico está implementado para o adapter local. Um futuro adapter
R2/S3 precisará implementar a recuperação adequada ao storage remoto.
OCR e biometria devem continuar usando o mesmo diretório quando compartilham o banco.

A limpeza **não apaga documentos ou comparações válidos só por idade**, nem seus
arquivos. Recursos `failed` também permanecem vinculados. Uma política de retenção
dos recursos de negócio será um checkpoint separado.

O código não consegue reconstruir bytes apagados fora da aplicação ou recuperar
um disco perdido. Esse cenário exige backup; SHA-256 não substitui o arquivo.

Execução manual:

```elixir
AikeStorage.Reconciliation.run(DocumentOcr.Repo)
# {:ok, %{blobs_deleted: ..., objects_checked: ...}}
```

Eventos de telemetria:
`[:aike, :storage, :compensation]` informa falhas de compensação;
`[:aike, :storage, :reconciliation]` informa exclusões de blobs e objetos verificados.
Não incluem bytes, nomes de documentos ou credenciais.

## Validação

Testes cobrem conflitos de chave, chaves alternativas para o mesmo recurso,
vínculos legados, rollback após enfileirar, proteção de blobs compartilhados,
falha/retry de exclusão, temporários abandonados, repetição de conclusão,
concorrência com conexões PostgreSQL independentes e encerramento forçado
do processo antes do commit.
