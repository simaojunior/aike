# Classificador local com Tesseract

O engine padrão em desenvolvimento e releases é `DocumentClassifier.Engine.Tesseract`,
escrito em Elixir. O pré-processamento usa OpenCV pelo `evision` (NIF pré-compilado,
empacotado pelo `mix release`) no app compartilhado `aike_vision`. Tesseract e Poppler
continuam como executáveis do sistema: o flake os fornece, e releases precisam deles no PATH.
Testes de contrato continuam com Fake; testes de integração executam o Tesseract real.

`DocumentClassifier.Engine.TesseractPython` (`priv/classify_text.py`) é a versão em Python
do mesmo pipeline. Fica só como referência para comparar resultados e precisa de Python
(Pillow) no PATH. O flake também fornece NumPy e OpenCV para Python.

## Desempenho

O classificador lê de forma progressiva: primeiro as passadas mais baratas e mais
prováveis, e para quando o resultado é conclusivo (tipo conhecido com qualidade aceitável;
no RG, também frente e verso).

- Foto: a orientação lê primeiro a imagem como chegou; as outras três rotações só rodam,
  em paralelo, sem palavras legíveis suficientes. Depois lê o recorte em cinza; o canal
  azul só roda se o resultado ficar em aberto.
- PDF: camada de texto e imagens embutidas primeiro. A página só é renderizada e lida se
  esses dados não bastam.

A leitura usa `--psm 3`: mais rápida e com menos ruído do que `--psm 11`.

| Entrada | Python (série) | Elixir |
|---|---|---|
| Foto de RG em pé | — | 1,0 s |
| Foto de RG de lado | 3,6 s | 1,5 s |
| CNH digital em PDF | 2,8 s | 0,7 s |

Limites por nó, recusa sob pico (`503` + `retry-after`) e dimensionamento:
`docs/capacity.md`.

## Escopo e contrato

- Entrada JSON/base64 ou multipart preservada. JPEG, PNG e PDF de uma página.
- Até 10 MB no engine e 20 milhões de pixels na imagem original; thumbnail até 2400 px.
  O limite HTTP do endpoint pode ser menor.
- PDF: OCR da página rasterizada pelo Poppler, das imagens embutidas (ampliadas até 3x) e
  leitura da camada de texto. A CNH digital embute o cartão como raster pequeno.
- Foto: uma passada rápida por rotação (0°, 90°, 180°, 270°) escolhe a orientação com mais
  palavras legíveis. O documento é recortado a partir da cor do papel em volta dessas palavras,
  com perfil de projeção para descartar reflexos estreitos. O OCR completo roda no recorte,
  em tons de cinza e no canal azul (tinta sobre papel de segurança verde ou azul).
- PDF de múltiplas páginas é rejeitado; não classificamos silenciosamente só a primeira.
- CNH: título junto de BRASIL. RG: título junto de BRASIL, ou pelo menos 3 marcadores
  exclusivos do RG (o título fica numa caixa girada que o OCR costuma perder).
  Evidência conflitante retorna unknown.
- CIN/passaporte e outros países não fazem parte desta versão. `country=BR` é o
  escopo legado do contrato, não evidência de nacionalidade para resultados unknown.
- Lado: CNH digital (selo "ASSINADO DIGITALMENTE" ou "certificado digital") é `single`.
  RG é `front`, `back` ou `single` conforme os marcadores de frente e verso encontrados.
  Nos demais casos, o lado permanece unknown.
- Multipart desconhecido mantém `data: []`; JSON mantém document/quality/confidence.
- `confidence=0.75` para regra positiva é um escore heurístico fixo, NÃO probabilidade calibrada.
- Qualidade é medida no recorte do documento, não na foto inteira. `acceptable` é verdadeiro
  somente sem issues:
  - `low_text_confidence`: mediana das confianças de palavras < 70 ou menos de 20 caracteres.
    A mediana resiste ao ruído de bordas e caixas de campo. Vale a mediana da melhor
    leitura (cinza, azul ou contraste esticado), não a de todas juntas: uma preparação
    fraca lê ruído do brasão e da trama e não deve recusar um documento legível.
  - `low_resolution`: menor lado do recorte < 320 px (cartão de 54 mm a 150 DPI).
  - `document_not_detected`: a foto não tem texto legível suficiente para localizar o documento.
  Não detecta fraude, autenticidade, reflexo ou desfoque de forma independente.
  `acceptable` não significa aprovação de KYC.
- Conteúdo inválido/fora dos limites retorna o erro existente invalid_request; indisponibilidade
  de dependências, falha de processamento ou timeout retorna service_unavailable. Falhas não são cacheadas.

## Operação e segurança

Cada chamada usa diretório aleatório privado (0700), removido em `after`, inclusive em falhas
esperadas e timeout. Nenhum texto reconhecido entra no banco ou nos logs. Os comandos recebem
argumentos sem shell, com nomes de arquivo internos. Cada subprocesso tem limite de 4s e o
processo completo é encerrado em 10s, incluindo seu grupo de processos. Uma queda abrupta da
VM pode deixar diretório temporário: a política de limpeza do tmp do host precisa estar ativa.
O limite de tempo não substitui limites de memória/concurrency do ambiente em produção.

Cache existente continua isolado por empresa, SHA-256 e versão. Versão atual:
`tesseract-por-rules-4` (pipeline em Elixir, `--psm 3`, ampliação bicúbica, etapa de contraste esticado e recorte que mantém os quadros brancos de foto e digital dentro do cartão). Mudar regras, pré-processamento, Tesseract ou traineddata exige
incrementar a versão antes de reaproveitar o cache. O flake.lock fixa o ambiente de desenvolvimento.

## Validação e trabalho restante

Testes sintéticos verificam extração real PNG/PDF, regras, conteúdo inválido e limites.
Não representam acurácia em documentos reais. Antes de considerar o classificador concluído:

1. Montar amostra autorizada e rotulada por pessoa/documento, separando avaliação de ajustes.
2. Medir precisão/recall por tipo, falsos positivos, desconhecidos, latência e memória.
3. Incluir fotos com reflexo, rotação, corte e versões diferentes de CNH/RG.
4. Definir suporte a lados e PDFs multipágina; calibrar confiança e avaliar qualidade visual.
5. Comparar com modelo visual somente se a referência inicial não atingir os critérios acordados.

Não colocar documentos pessoais em Git. Para smoke com arquivo local:
`CLASSIFIER_FILE=./cnh.jpg bash scripts/smoke-classifier.sh` (requer credenciais já documentadas).

## Diagnóstico de HTTP 503

A resposta pública usa `service_unavailable`. O log da mesma requisição distingue
`auth.introspection.failed` (consulta ao backoffice), `classifier.ocr.failed`
(execução local do OCR) e `classifier.failed` (engine ou resultado inválido).
Os diagnósticos não incluem credenciais, texto extraído nem saída bruta dos comandos.

- `missing_aike_auth_token`: exporte `AIKE_AUTH_TOKEN` antes de iniciar o servidor,
  com o mesmo valor no backoffice e nos processadores. É o token interno, distinto
  do segredo da service account enviado pelo cliente.
- `invalid_backoffice_auth_url` ou `connection_failed`: confira `BACKOFFICE_AUTH_URL`
  e a disponibilidade do backoffice (porta 4003 no desenvolvimento).
- `missing_runtime_dependency`: execute dentro de `nix develop`, com
  Tesseract e Poppler disponíveis.
- `timeout`: o subprocesso excedeu seu limite de execução.
- `ocr_command_failed`: Tesseract ou Poppler terminou com erro; confira a instalação
  e o suporte ao idioma `por`.

Depois de corrigir variáveis de ambiente, reinicie o servidor e repita o upload.
Use o `request_id` para relacionar o diagnóstico ao status HTTP.
