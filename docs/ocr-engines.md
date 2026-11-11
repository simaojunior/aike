# OCR substituível e proveniência — checkpoint 4

`DocumentOcr.OCR.Engine` mantém o contrato `extract(binary(), keyword())` retornando
`{:ok, map()}` ou `{:error, term()}`. Adapters registrados:

| Módulo | Versão | Uso |
|---|---|---|
| `DocumentOcr.OCR.Fake` | `fake-1` | testes (`config/test.exs`); resposta fixa |
| `DocumentOcr.OCR.Tesseract` | `tesseract-5-por-5` | padrão; Elixir + OpenCV (`aike_vision`); linhas com geometria |
| `DocumentOcr.OCR.TesseractPython` | `tesseract-5-por-1` | referência em Python (`priv/ocr_lines.py`) |

Novos documentos usam `DocumentOcr.OCR.Tesseract`, `tesseract-5-por-5` e o extrator
`br-labels-3`. Documentos criados antes continuam com a configuração gravada neles, e a
reutilização de resultado só aceita a mesma engine e versão.

O motor Tesseract (`tesseract-5-por-5`):

- Foto: encontra a orientação (0° primeiro; as outras rotações só sem texto suficiente),
  recorta o documento e, num cartão aberto (proporção acima de 2,2:1, como o RG com frente e
  verso lado a lado), lê cada metade separadamente.
- PDF: imagens embutidas na resolução nativa; sem elas, a página renderizada.
- Cada linha traz as caixas das palavras (`words`), para separar rótulos impressos lado a lado.
- Passadas: cinza, canal azul e cinza esticado, todas com `--psm 4`. O cinza esticado
  leva o papel ao branco e a tinta clara ao preto. Assim o OCR lê os valores em vermelho
  da CNH (categoria, nº de registro, validade). O RG tem mais uma passada esparsa
  (`--psm 11`) no canal azul, para campos isolados como a data de nascimento.

O extrator `br-labels-3` lê cada campo pelo rótulo impresso e escolhe, entre as passadas,
o valor válido, mais repetido e com maior confiança. O pipeline junta as linhas de todas
as imagens do documento (frente primeiro), porque o RG imprime os dados no verso.

| Tipo | Módulo | Campos |
|---|---|---|
| `cnh` | `DocumentOcr.Extraction.CNHLabels` | obrigatórios `full_name`, `cpf`, `birth_date`; opcionais: documento de identidade, filiação, categoria, registro, validade, 1ª habilitação, local e data de emissão |
| `rg` | `DocumentOcr.Extraction.RGLabels` | obrigatórios `full_name`, `rg_number`, `birth_date`; opcionais: expedição, filiação, naturalidade, documento de origem, `cpf` |

No RG, o rótulo da data de nascimento é pequeno e claro. Sem ele, a data mais antiga de
duas ou mais é a de nascimento, porque a data de expedição é sempre posterior. Com uma
data só, o campo fica vazio e o documento vai para revisão.

Um tipo sem extrator registrado na versão ativa é recusado na criação (`422`), em vez de
falhar depois no worker. Capacidade e concorrência: `docs/capacity.md`.

## Seleção e registro

Configuração atual em `config/config.exs`:

```elixir
config :document_ocr,
  ocr_engine: DocumentOcr.OCR.Tesseract,
  ocr_engine_version: "tesseract-5-por-5",
  extractor_version: "br-labels-3",
  pipeline_version: "2026.11.0",
  ocr_engines: [
    {DocumentOcr.OCR.Fake, "fake-1"},
    {DocumentOcr.OCR.Tesseract, "tesseract-5-por-5"},
    {DocumentOcr.OCR.TesseractPython, "tesseract-5-por-1"}
  ],
  extractors: %{
    {"cnh", "fake-cnh-1"} => DocumentOcr.Extraction.CNH,
    {"cnh", "br-labels-3"} => DocumentOcr.Extraction.CNHLabels,
    {"rg", "br-labels-3"} => DocumentOcr.Extraction.RGLabels
  }
```

As quatro primeiras chaves selecionam a configuração de **novos documentos**.
`ocr_engines` lista pares `{módulo, versão}` disponíveis para documentos em andamento;
`extractors` associa `{tipo, versão}` ao módulo de extração. Para trocar a engine,
implemente o behaviour, registre o novo par e selecione-o em `ocr_engine` e
`ocr_engine_version`. Não é necessário mudar controller, filas ou workers.

Mantenha os registros antigos enquanto houver documentos usando essas versões.
Um registro ausente causa erro/retry; nunca há fallback silencioso para o adapter
atual. Remover uma versão permanentemente leva a failed após esgotar as tentativas.
Módulos são resolvidos exclusivamente pelo registro confiável em configuração;
strings do banco não são convertidas em novos atoms nem executadas como módulos.

## Fixação por execução

`Documents.create_document/1` captura engine e versões no momento da criação.
Essa configuração é persistida na mesma transação que cria documento/imagens e
enfileira PreprocessDocument.
Os quatro campos não são aceitos dos atributos do cliente nem por changeset público.
Configuração ausente, versão não registrada ou módulo sem callback impede criar
documento/job; a API responde 503 genérico.

`pipeline_version`, `ocr_engine`, `ocr_engine_version` e `extractor_version` ficam no
documento. Cada etapa usa esse registro, e `document_results` copia esses mesmos
valores ao persistir/upsert. Logs também usam os valores do documento. Alterar os
defaults depois da criação, inclusive entre OCR e gravação do resultado, não muda
a proveniência dessa execução. A versão do pipeline é um identificador de configuração,
não um mecanismo de replay de código antigo.

O dispatch de OCR passa `document_type` e `engine_version` em opts. O adapter precisa
respeitar essa versão ou retornar erro. O extractor fake espera um mapa com chave
`"text"` contendo itens `"text"`/`"confidence"` (0..1). A escolha front/single/back
e a validação canônica continuam no pipeline, fora da engine.

`OCR.extract/2` continua disponível para chamadas diretas usando a configuração atual;
o pipeline usa `OCR.extract/3` com o documento capturado. A extração de campos passa
por `DocumentOcr.Extraction`, que resolve o extractor pela versão do documento.

## Migration e dados existentes

`20261005000001_pin_processing_configuration` adiciona três colunas a documents;
pipeline_version já existia. O banco impede configuração parcialmente preenchida.
As colunas aceitam null em conjunto apenas para representar registros legados.
A criação via contexto sempre preenche os quatro campos.

Aplique antes de executar o código novo:

```bash
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
```

A migration não deduz versões antigas da configuração atual nem reescreve resultados.
Documentos terminais antigos e seus resultados continuam disponíveis. Documentos
pendentes/em processamento sem proveniência registrada não podem completar com
versões inventadas: falham após retries. Se houver fila antiga, conclua-a antes da
atualização ou use o [endpoint de reprocessamento](reprocessing.md) após atualizar
para o checkpoint 5, que inicia uma execução identificada com a configuração atual.
Não se afirma retroativamente que metadados gravados pelo código
anterior identificam com certeza a engine que produziu o OCR.

## Testes e limites

`provenance_test.exs` exerce uma engine e um extractor alternativos exclusivamente
de teste, incluindo resposta HTTP, troca de configuração entre etapas, retry com
registro removido/restaurado, versão de extractor indisponível, upsert, erro 503,
atributos falsificados e compatibilidade com documentos legados.

Os registros devem ser tratados como imutáveis: não remapear a mesma versão para
outro código/modelo. Essa política e o cumprimento de engine_version pelo adapter
são necessários para a proveniência; não há fingerprint de binário/modelo, arquivo
de modelos históricos, garantia de replay ou versionamento de regras de validação.
Alterar a implementação de um módulo mantendo o mesmo nome/versão não é detectado.
Configuração deve ser publicada coerentemente por deploy; hot reload de múltiplas
chaves não é uma operação transacional oferecida por este checkpoint.

Inferência ocorre fora da transação longa e bytes fake continuam em JSONB. Mover
esses bytes para storage privado, definir timeout/cancelamento controlado no processo de
execução e avaliar
modelos são checkpoints separados. Identidade de execução e reprocessamento foram
adicionados no checkpoint 5; consulte [reprocessing.md](reprocessing.md).

Verificação deste checkpoint: migration aplicada em dev/test; `mix format
--check-formatted`, `mix compile --warnings-as-errors` e **47 testes** passaram.
O smoke test HTTP percorreu os cinco jobs e chegou a completed. Os testes incluem
27 casos OCR, 19 classifier e 1 core; as engines alternativas existem só nos testes.
