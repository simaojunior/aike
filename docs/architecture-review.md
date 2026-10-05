# Revisão de arquitetura — checkpoint 3

Escopo: seção 47 do guia, após os dois fluxos fake. Inspeção realizada antes das
correções deste checkpoint. Nenhuma infraestrutura ou modelo de ML será introduzido.

## Diagnóstico inicial

| Área | Evidência e avaliação |
| --- | --- |
| Fronteiras e dependências | Cada API possui Endpoint/Application próprios. Classifier depende de Phoenix/Bandit/Jason e kyc_core; não depende de OCR, Ecto ou Oban. OCR não chama classifier. Correto. |
| Shared core | Quatro módulos pequenos de vocabulário, sem framework/persistência. Correto; listas em constraints SQL representam o contrato persistido e não devem depender de módulos mutáveis nas migrations. |
| Ecto e Oban | Repo, migrations, schemas, filas e workers pertencem somente ao OCR. Correto. |
| Configuração de produção | runtime.exs exige DATABASE_URL/SERVICE_TOKEN do OCR mesmo para classifier isolado; não há releases nomeadas. Corrigir com releases por serviço e seleção de runtime pelo nome da release. |
| Estado do documento | Processor concentra alterações, mas decide a partir do struct recebido. Um struct processing antigo pode sobrescrever completed no banco. Corrigir relendo a linha com lock na transição. |
| Jobs e idempotência | Criação e enfileiramento iniciais atômicos; lock por documento, upserts e próximo job na mesma transação; unique constraints de resultado/artefato. Bom para a execução única atual. Não resolve reprocessamento/histórico. |
| Erros dos jobs | O rescue de Pipeline recarrega com get_document! o mesmo documento que pode não existir. Um job órfão lança novamente e gasta retries. Corrigir cancelamento explícito e erro sanitizado quando o banco está indisponível. |
| Seleção de imagem | Ordenação alfabética põe back antes de front; ExtractFields usa o primeiro output. Corrigir escolha explícita front, depois single, depois back no contrato fake. |
| CPF | CNH.extract remove qualquer caractere não numérico; uma letra inserida num CPF válido desaparece e o valor passa no checksum. Corrigir remoção apenas dos separadores aceitos pela validação. |
| Capacidade do OCR | HTTP rejeita RG, mas Document.changeset aceita RG e o pipeline só possui extractor CNH. Alinhar o changeset à capacidade atual para não criar trabalho que necessariamente falha. |
| HTTP | POST OCR 202, leitura separada, resultado pendente 409; classifier 200 inclui unknown/baixa qualidade, 422 para request e 503 para adapter. Coerente. OCR ainda não diferencia todas as indisponibilidades de infraestrutura no POST. |
| Autenticação | Classifier rejeita token vazio; OCR aceita configuração vazia e compara com Bearer vazio. Alinhar fail-closed, autenticar antes do parser e exigir token em produção mesmo se faltar config runtime. |
| Banco | UUIDs, FKs, índices e unicidade de resultado/artefato/lado presentes. Não duplicar índices de document_id já cobertos pelos índices compostos. Sem migration necessária neste checkpoint. |
| Logging | Parâmetros HTTP filtrados, SQL sem logs, erros de adapters sanitizados. Stage é enviado ao Logger, mas não está no formatter; incluí-lo. App/external/request IDs devem continuar livres de PII por contrato do cliente. |
| Testes | 58 testes cobrem fluxo fake, retries, reprocessamento, concorrência, fixtures, HTTP e releases. A separação entre adapters externos e transações curtas tem regressão específica. |

## Correções de baixo risco planejadas

1. Releases e runtime independentes, sem compartilhar código de infra no core.
2. Estado atual sob lock ao validar transições; impedir reversão de terminal por struct antigo.
3. Cancelar job de documento ausente sem exceção recursiva.
4. Escolher explicitamente imagem front/single/back e preservar caracteres inválidos no CPF.
5. Rejeitar RG na criação de domínio enquanto não há extractor.
6. Auth OCR fail-closed e auth obrigatória em produção para ambas as APIs.
7. Incluir stage nos metadados exibidos e adicionar testes de regressão.

## Pendências que exigem outro checkpoint

- **Resolvido neste checkpoint:** storage/OCR rodam fora da transação com lock. O
  worker marca processing, faz a chamada externa e usa transação curta para validar
  run_id, persistir e enfileirar. Timeout/cancelamento cooperativo dos adapters
  reais ainda é necessário.
- Artefatos binários são base64 em JSONB, sem retenção. Mover para storage privado,
  definir ciclo de vida, limites e auditoria antes de dados reais.
- Uniqueness do Oban depende da retenção dos jobs. Upserts e estado terminal protegem
  retries atuais. **Checkpoint 5:** run_id e reprocessamento transacional isolam
  execuções; jobs/structs antigos são recusados inclusive no tratamento de falha.
  Ainda não há marcador durável de conclusão por etapa nem histórico de resultados.
- **Resolvido no checkpoint 4:** engine e versões agora são capturados no documento
  na criação e usados por workers, logs e resultados. Adapters versionados e testes
  de configuração entre etapas estão descritos em [ocr-engines.md](ocr-engines.md).
  A preservação do código/modelo de cada versão continua sendo responsabilidade do
  deploy; ainda não há fingerprint de artefatos ou garantia de replay histórico.
- Timeout abrupto ou queda do banco na última tentativa pode impedir gravar failed.
  Falta reconciliação entre jobs descartados e documentos processing.
- Catch/rescue sanitiza dados, mas agrupa causas distintas; falta taxonomia de erro
  segura, métricas de latência/filas, rastreamento e política de timeout dos adapters.
- POST OCR precisa distinguir indisponibilidade de infraestrutura de request inválido
  e definir idempotency key de cliente (app_id/external_id hoje é índice não único).
- GET result retorna 409 também para failed sem resultado; documentar política de erro
  terminal mais expressiva quando o consumidor for integrado.
- RG, combinação frente/verso, campos adicionais e histórico não estão implementados.
  Reprocessamento foi entregue no checkpoint 5 ([reprocessing.md](reprocessing.md)).
  O classifier fake não demonstra capacidade real de reconhecimento.
- CPF/data/thresholds são regras provisórias; ausência de campos/confiança inválida é
  barrada pelo extractor atual, não por validação geral de um contrato de resultado.
- HTTPS, retenção, proteção contra abuso, armazenamento privado e auditoria são
  trabalho de produção. Releases locais não representam implantação dessa infraestrutura.

## Verificação

- Os seis testes de regressão foram executados **antes** das correções e reproduziram
  os seis problemas: CPF corrompido, auth vazia, job órfão, RG, estado antigo e verso.
- Após as correções, `mix test` passou com **58 testes** (1 core, 38 OCR, 19 classifier).
- `mix compile --warnings-as-errors` passou para as aplicações; formatação aplicada.
- `MIX_ENV=prod mix release document_classifier` e `mix release document_ocr` com
  o mesmo MIX_ENV geraram as releases. A compilação nova das dependências de produção
  mostrou uma depreciação de `xref: [exclude: ...]` no Plug, sem impedir o build;
  não se modificou código de dependência neste checkpoint.
- A release classifier iniciou isolada sem DATABASE_URL/SERVICE_TOKEN/SECRET_KEY_BASE
  do OCR; autenticação e classificação foram verificadas via Plug.
- A release OCR iniciou sem classifier e ignorou CLASSIFIER_PORT inválida. Auth
  verificada via Plug e conexão PostgreSQL confirmada por SELECT 1, sem gravações.
- `mix format --check-formatted` e `mix compile --warnings-as-errors` finais passaram.
- Nenhuma falha restante nos testes/verificações executados. Não foram feitos testes
  de carga, recuperação de queda de processo/banco ou implantação fora de NixOS.

## Correções aplicadas

Todos os sete grupos planejados acima foram implementados. `mix.exs` declara duas
releases e runtime seleciona apenas o serviço da release. Tokens obrigatórios são
validados sem expor valores, e os Plugs negam acesso sem configuração de auth em
produção. Processor relê com lock; Pipeline cancela documentos ausentes e sanitiza
falhas secundárias. Escolha de imagem e normalização de CPF foram corrigidas;
changeset rejeita RG, e stage aparece no formatter. Nenhuma migration ou modelo ML
foi adicionado. Os itens de maior escopo permanecem na seção de pendências.
