# LoomisFlow Studio

App **gratuito, ilimitado e de código aberto** (iOS + Android, um único código em Flutter) que transforma
qualquer retrato em um passo a passo do **Método Andrew Loomis**, com decalque na tela e projeção em AR sobre
o caderno físico.

Sem assinatura, sem moedas, sem limite diário, sem tutorial bloqueado, sem conta, sem marca d'água.
Nenhuma foto sai do aparelho (a única chamada de rede é a busca opcional da Biblioteca de Referências).

> **Status honesto:** o código foi escrito por completo, mas **não foi compilado nem executado** no ambiente
> em que foi gerado (não havia Flutter/Dart instalado). Espere ajustes pequenos no primeiro `flutter run`
> (versões de plugins, avisos do analisador). Veja "Limitações" no fim.

## Como rodar

```bash
# 1) instale o Flutter ≥ 3.27 (https://docs.flutter.dev/get-started/install)
# 2) dentro desta pasta:
./tool/setup_platforms.sh      # gera android/ e ios/, aplica permissões, roda pub get
flutter test                   # testes da geometria Loomis
flutter run --release          # use um aparelho REAL (ML Kit não roda no simulador iOS arm64)
```

## Arquitetura

```
lib/
├─ main.dart                  entrada; tema escuro; AppScope (InheritedNotifier)
├─ core/
│  ├─ face_analyzer.dart      ML Kit Face Detection (on-device): olhos, nariz, boca, sobrancelhas, oval
│  ├─ loomis_guide.dart       MODELO do guia: medidas do rosto → geometria Loomis (referencial da cabeça)
│  ├─ guide_renderer.dart     DESENHO dos 8 passos, com fade contínuo (0..7); grade; traços do usuário
│  ├─ image_utils.dart        EXIF, redução, e mapa de luz/sombra (posterização 3 níveis, local)
│  ├─ models.dart             Project, StrokeData
│  ├─ storage.dart            pasta por projeto: reference.jpg, shading.png, meta.json, strokes.json
│  ├─ exporter.dart           PNG comparativo (foto | esboço) e time-lapse GIF — sem marca d'água
│  ├─ app_state.dart          ChangeNotifier: lista de projetos, projeto atual, pipeline de criação
│  ├─ spring.dart             física de mola (SpringSimulation), PressableScale, rota com mola
│  └─ theme.dart              paleta dark minimalista
├─ widgets/
│  ├─ step_slider.dart        barra de passos; solta e "encaixa" no passo com mola
│  └─ radial_menu.dart        menu radial flutuante, ARRASTÁVEL (fica longe da mão que desenha)
└─ features/
   ├─ shell.dart              navegação inferior: Estúdio · Referências · Meu Progresso
   ├─ studio/                 foto/câmera → guia → barra de passos → abrir decalque/AR
   ├─ trace/                  decalque na tela (gestos, Modo Foco) e AR com câmera
   ├─ library/                Wikimedia Commons (API aberta; só licenças livres)
   └─ gallery/                projetos salvos, exportar/compartilhar, renomear, excluir
```

### Pipeline de IA (100% local)

```
foto ─► normaliza (EXIF, ≤1600px) ─► ML Kit (rosto) ─► FaceMeasurements
                                                         │
                       sem rosto? ─► guia padrão ◄───────┤
                                                         ▼
                                  LoomisGuide (esfera, terços, mandíbula, traços)
foto ─► luminância ─► posteriza em 3 níveis ─► shading.png (guia de sombreamento)
```

A geometria é feita no **referencial da cabeça** (origem entre os olhos, eixo X na linha dos olhos), então
a guia acompanha a inclinação (*roll*) e a rotação lateral estimada (*yaw*, pela posição do nariz).

### Os 8 passos (barra deslizante)

| # | Passo | O que aparece |
|---|-------|---------------|
| 1 | Esfera craniana | círculo base do crânio |
| 2 | Corte do plano lateral | duas elipses laterais (o "corte" de Loomis) |
| 3 | Linhas central e das sobrancelhas | meridiano (curvo se o rosto está virado) + equador |
| 4 | Terços | linhas do cabelo, do nariz e do queixo |
| 5 | Mandíbula, queixo e orelhas | linhas da mandíbula e orelhas entre sobrancelha e nariz |
| 6 | Posicionamento dos traços | olhos, sobrancelhas, nariz, boca em blocos |
| 7 | Contorno e detalhes | contorno suave e polilinhas de olhos/nariz/lábios do ML Kit |
| 8 | Guia de sombreamento | mapa de sombra/meio-tom recortado na cabeça |

### Gestos no decalque

| Gesto | Ação |
|-------|------|
| 1 dedo | desenha |
| pinça com 2 dedos | zoom (e arrastar com 2 dedos move a vista) |
| toque rápido com 2 dedos | **desfazer** |
| toque rápido com 3 dedos | **refazer** |
| botão central do menu radial | abre o leque; arraste-o para qualquer canto |
| *Mover decalque* (no menu) | 1 dedo move foto+guia; 2 dedos escalam e giram |
| *Modo Foco* | esconde toda a interface; só sobra uma alça quase invisível no canto superior direito |

Ajustes (painel): opacidade da foto, opacidade da guia, escala, rotação, grade 8×8, espessura e cor do traço.

### Armazenamento

Cada retrato é uma pasta em `ApplicationDocuments/projects/<id>/`. Traços são salvos 600 ms após cada
pincelada e ao sair da tela (escrita atômica `.tmp` → rename).

## Requisitos × implementação

| Requisito | Onde |
|-----------|------|
| Grátis/ilimitado, sem moedas | não existe código de cobrança, cota ou login |
| IA local | `face_analyzer.dart`, `image_utils.dart` |
| Foto ou câmera | `studio_screen.dart` (`image_picker`) |
| Passos Loomis + barra | `guide_renderer.dart`, `step_slider.dart` |
| Decalque na tela + Modo Foco | `trace/` |
| AR sobre caderno | `trace/ar_screen.dart` |
| Dark + mola | `theme.dart`, `spring.dart` |
| Gestos, menu radial | `trace_screen.dart`, `radial_menu.dart` |
| 3 abas | `shell.dart` |
| Salvamento + exportação | `storage.dart`, `exporter.dart`, `gallery_screen.dart` |

## Limitações (leia antes de prometer algo a alguém)

- **Time-lapse é GIF animado, não MP4.** Gerar MP4 exige um codificador nativo (MediaCodec no Android,
  AVAssetWriter no iOS) ou FFmpeg, e as builds de FFmpeg para Flutter têm problemas de licença/manutenção.
  O GIF abre em qualquer app de mensagens. MP4 pode ser adicionado depois via *platform channel*.
- **"AR" é projeção sobre a câmera, não rastreamento.** A guia é uma sobreposição 2D que você encaixa na
  folha e trava; se o celular mexer, ela não acompanha. Para uso real, apoie o aparelho em um tripé.
  Rastreamento de plano (ARCore/ARKit) seria um passo seguinte.
- **A guia Loomis é geométrica, derivada de pontos do ML Kit** (não é um modelo generativo). Funciona
  melhor com rosto de frente ou 3/4; em perfil, rostos pequenos ou muito cobertos a precisão cai, e o
  app usa as proporções clássicas como plano B. A rotação lateral (*yaw*) é estimada só pelo nariz.
- **O mapa de sombreamento é uma posterização simples** de luminância, não uma análise de iluminação.
- **Biblioteca online:** usa a API pública do Wikimedia Commons e filtra por licença livre, mas várias
  licenças CC exigem **atribuição** ao compartilhar; o app mostra a licença na grade, não a embute nas
  exportações. Sem internet, a aba mostra um aviso (o resto do app funciona).
- ML Kit exige **iOS 15.5+** e aparelho real no iOS; confirme as versões mínimas no README do plugin
  `google_mlkit_face_detection`, pois mudam entre versões.
- Não há testes de interface; os testes incluídos cobrem apenas a geometria e a serialização.

## Licença

Sugestão: MIT ou GPL-3.0 (escolha e adicione o arquivo `LICENSE`). As dependências são todas gratuitas.

## Atualizações

- **Aba Pesquisar** (`lib/features/browser/`): mini-navegador (WebView) com DuckDuckGo, Google, Pinterest e Unsplash.
  Segure o dedo numa foto para usá-la como referência (ou ligue o "Modo toque"). Para estudo pessoal;
  respeite os direitos do autor ao compartilhar.
- Navegação inferior agora tem 4 abas: Estúdio · Referências · Pesquisar · Progresso.
- Detecção de rosto: segunda tentativa em modo simples e, se falhar, o motivo aparece na tela do Estúdio.
