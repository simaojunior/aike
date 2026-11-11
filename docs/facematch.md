# Facematch

O facematch compara o rosto de uma selfie com o rosto de um documento (CNH ou RG). Roda
no próprio serviço de biometria, com modelos abertos do OpenCV; nenhuma imagem sai para
outro serviço.

## Motor

| Etapa | Como |
|---|---|
| Arquivos | JPEG, PNG ou PDF de uma página. No PDF, as imagens embutidas vêm primeiro (a CNH digital guarda a foto ali), depois a página renderizada |
| Orientação | sem rosto na posição dada, a imagem é tentada nas outras três rotações |
| Detecção | YuNet (`face_detection_yunet_2023mar.onnx`, licença MIT), na imagem reduzida a 1280 px no lado maior |
| Escolha do rosto | selfie: uma pessoa só; um segundo rosto nítido (score ≥ 0,8 e área ≥ 25% do principal) recusa a selfie. Documento: o rosto de maior score × área. Rosto com menos de 40 px de largura é pequeno demais |
| Comparação | SFace (`face_recognition_sface_2021dec.onnx`, licença Apache 2.0): o rosto é alinhado pelos olhos, nariz e boca e vira um vetor; a similaridade é o cosseno entre os dois vetores |

Versão do motor: `opencv-yunet2023mar-sface2021dec-1`. Uma mudança de modelo, limite ou
etapa exige uma versão nova (`engine_version`), porque o resultado de comparações
anteriores é reutilizado por versão.

Tempo medido: de 0,6 a 0,8 s por comparação com um PDF, em CPU.

## Decisão

| Similaridade | `decision` | `matched` |
|---|---|---|
| ≥ `approve_at` (0,5) | `approved` | `true` |
| ≥ `review_at` (0,363) | `manual_review` | `true` |
| abaixo, ou sem rosto utilizável | `rejected` | `false` |

```elixir
config :biometrics, decision: [approve_at: 0.5, review_at: 0.363]
```

O 0,363 é o limite que o OpenCV indica para o SFace em fotos comuns. Selfie contra foto
impressa de documento é um caso mais difícil (idade, luz, impressão). **Antes de usar em
produção, meça os dois limites** com pares autorizados de selfie e documento, da mesma
pessoa e de pessoas diferentes, e ajuste a configuração.

Medições locais com documentos reais (fora do Git):

| Par | Similaridade |
|---|---|
| mesma foto da CNH em duas resoluções | 0,97 |
| CNH × RG de pessoas diferentes | 0,22 |

Ainda falta medir selfie real contra documento.

## Modelos

Os modelos não ficam no Git. `scripts/fetch_face_models.sh` baixa os dois do OpenCV Zoo
e confere o SHA-256; um arquivo diferente é recusado.

```bash
scripts/fetch_face_models.sh            # para var/models/
scripts/fetch_face_models.sh /app/models
```

A pasta vem de `AIKE_FACE_MODELS_DIR` (padrão `var/models/`). A imagem `biometrics` já
baixa os modelos no build. Sem os modelos, a comparação falha com
`face_models_unavailable` e a sessão termina como `failed` depois das tentativas.

Os testes que rodam os modelos reais têm a tag `:face_models` e só rodam quando os
arquivos existem.

## Limites

- **Sem prova de vida.** Uma foto do titular, impressa ou numa tela, passa no
  facematch. A prova de vida é um passo separado, ainda não implementado.
- Não consulta bases oficiais de biometria.
- **LGPD:** biometria é dado pessoal sensível (art. 11). O cliente precisa de base legal
  e consentimento; defina retenção curta para selfies e documentos e restrinja o acesso
  ao bucket.
- O modelo foi treinado em bases públicas. O acerto pode variar entre grupos de pessoas;
  a calibração deve incluir amostras variadas.
