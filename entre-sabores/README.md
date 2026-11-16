# Entre Sabores

Aplicativo de receitas em Flutter e Dart, baseado no wireframe enviado e conectado à API do projeto `api-dsdm-`. Favoritos e lista de compras ficam salvos localmente.

## Rodar no Windows

1. Instale o Flutter e o Visual Studio 2022 ou mais recente, com a carga de trabalho **Desenvolvimento para desktop com C++**.
2. Inicie a API de receitas na porta 3000.
3. Abra esta pasta no terminal e execute:

   ```powershell
   flutter pub get
   flutter run -d windows
   ```

O app se conecta por padrão a `http://localhost:3000`.

## Rodar no Android

Instale o Android Studio/SDK ou conecte um celular. Com a API iniciada, execute `flutter pub get` e `flutter run`. O emulador Android usa `http://10.0.2.2:3000`. Em celular físico, configure `--dart-define=API_BASE_URL=http://IP_DO_COMPUTADOR:3000` e mantenha os aparelhos na mesma rede.

Para gerar APK de depuração: `flutter build apk --debug`.

O modo de depuração Android permite HTTP para a API local. Para uma versão publicada, use API com HTTPS.

## Funcionalidades

- Início com receitas e categorias, busca e filtros.
- Detalhes e modo de preparo.
- Favoritos e lista de compras no armazenamento local.
- Cadastro de receitas via `POST /receitas`.
- Perfil e navegação inferior.

O backend atual não oferece autenticação, avaliações ou envio de imagens; essas partes do wireframe precisam de endpoints adicionais. As tabelas do PostgreSQL devem ser criadas com os scripts SQL da API.
