import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const orange = Color(0xFFD64220);
const ink = Color(0xFF33241F);
const muted = Color(0xFF887970);
const paper = Color(0xFFFFFAF5);
const cream = Color(0xFFF6E8D9);
const line = Color(0xFFEEE1D5);
const fallbackCategories = [
  'Almoço',
  'Café da manhã',
  'Jantar',
  'Lanche',
  'Sobremesa',
  'Bebida',
];
const foodIcons = [
  Icons.cake_outlined,
  Icons.ramen_dining,
  Icons.set_meal,
  Icons.breakfast_dining,
  Icons.soup_kitchen,
  Icons.local_cafe,
];

/// Se a sua API NÃO tiver a rota GET /receitas/:id, troque para false.
/// Os detalhes passam a usar só os dados que já vieram da lista.
const bool fetchDetailsFromApi = true;

void main() => runApp(const EntreSaboresApp());

class ApiException implements Exception {
  ApiException(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}

String friendlyError(Object error) {
  if (error is SocketException) {
    return 'Não consegui conectar à API. Confira se ela está ligada.';
  }
  if (error is TimeoutException) {
    return 'A API demorou demais para responder. Tente novamente.';
  }
  if (error is HttpException) {
    return 'Falha de comunicação com a API.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.minutes,
    required this.portions,
    required this.ingredients,
    required this.steps,
    this.imageUrl,
  });
  final String id;
  final String name;
  final String category;
  final String minutes;
  final String portions;
  final List<String> ingredients;
  final String steps;
  final String? imageUrl;

  bool get hasTime => minutes.trim().isNotEmpty && minutes.trim() != '—';
  bool get hasPortions => portions.trim().isNotEmpty && portions.trim() != '—';
  bool get hasSteps => steps.trim().isNotEmpty;
  String get timeLabel => hasTime ? '$minutes min' : 'Tempo não informado';
  String get portionsLabel =>
      hasPortions ? '$portions porções' : 'Porções não informadas';

  factory Recipe.fromJson(Map<String, dynamic> json) {
    dynamic rawIngredients =
        json['ingredientes'] ?? json['ingredients'] ?? const [];
    if (rawIngredients is String) {
      try {
        rawIngredients = jsonDecode(rawIngredients);
      } catch (_) {
        rawIngredients = rawIngredients.split(RegExp(r'\r?\n'));
      }
    }
    final list = rawIngredients is List
        ? rawIngredients
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
        : <String>[];
    final image = (json['imagem_url'] ??
            json['imagemUrl'] ??
            json['imagem'] ??
            json['foto'])
        ?.toString()
        .trim();
    return Recipe(
      id: (json['id'] ?? json['nome'] ?? '').toString(),
      name: (json['nome'] ?? json['name'] ?? 'Receita sem nome').toString(),
      category: (json['categoria_nome'] ??
              json['categoria'] ??
              json['category'] ??
              'Receita da casa')
          .toString(),
      minutes: (json['tempo_preparo'] ??
              json['tempoPreparo'] ??
              json['tempo'] ??
              '—')
          .toString(),
      portions: (json['porcoes'] ?? json['rendimento'] ?? '—').toString(),
      ingredients: list,
      steps:
          (json['modo_preparo'] ?? json['modoPreparo'] ?? json['preparo'] ?? '')
              .toString(),
      imageUrl: (image == null || image.isEmpty) ? null : image,
    );
  }
}

class RecipeApi {
  RecipeApi()
      : baseUrl = const String.fromEnvironment('API_BASE_URL').trim().isNotEmpty
            ? const String.fromEnvironment('API_BASE_URL').trim()
            : (Platform.isAndroid
                ? 'http://10.0.2.2:3000'
                : 'http://localhost:3000');
  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final request = await _client
        .openUrl(method, Uri.parse('$baseUrl$path'))
        .timeout(const Duration(seconds: 10));
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final text = await response.transform(utf8.decoder).join();
    dynamic data;
    if (text.trim().isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = <String, dynamic>{'mensagem': 'Resposta inválida da API.'};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data is Map
          ? (data['mensagem'] ??
              data['message'] ??
              data['erro'] ??
              'A API retornou ${response.statusCode}.')
          : 'A API retornou ${response.statusCode}.';
      throw ApiException(message.toString(), response.statusCode);
    }
    return data;
  }

  Future<List<Recipe>> getRecipes() async =>
      _asRecipes(await request('/receitas'));

  Future<Recipe> getRecipe(String id) async {
    dynamic data = await request('/receitas/${Uri.encodeComponent(id)}');
    if (data is List && data.isNotEmpty) data = data.first;
    if (data is Map && data['receita'] is Map) data = data['receita'];
    if (data is! Map) throw ApiException('Receita não encontrada.', 404);
    return Recipe.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<Recipe>> getCategoriesRecipes({
    String? category,
    String? ingredients,
    String mode = 'todos',
  }) async {
    final params = <String, String>{};
    if (category != null && category.isNotEmpty) params['categoria'] = category;
    if (ingredients != null && ingredients.isNotEmpty) {
      params['ingredientes'] = ingredients;
      params['modo'] = mode;
    }
    return _asRecipes(
      await request('/receitas/filtrar?${Uri(queryParameters: params).query}'),
    );
  }

  Future<List<Recipe>> searchRecipes(String name) async => _asRecipes(
        await request(
          '/receitas/buscar?${Uri(queryParameters: {'nome': name}).query}',
        ),
      );

  Future<List<dynamic>> getCategories() async {
    final data = await request('/categorias');
    return data is List ? data : <dynamic>[];
  }

  Future<void> createRecipe(Map<String, dynamic> body) async {
    await request('/receitas', method: 'POST', body: body);
  }

  Future<void> updateRecipe(String id, Map<String, dynamic> body) async {
    await request(
      '/receitas/${Uri.encodeComponent(id)}',
      method: 'PUT',
      body: body,
    );
  }

  Future<void> deleteRecipe(String id) async {
    await request('/receitas/${Uri.encodeComponent(id)}', method: 'DELETE');
  }

  List<Recipe> _asRecipes(dynamic value) => value is List
      ? value.whereType<Map<String, dynamic>>().map(Recipe.fromJson).toList()
      : <Recipe>[];
}

/// Favoritos e lista de compras ficam no armazenamento do aparelho
/// (shared_preferences), que sobrevive ao fechar e reabrir o app.
/// Favoritos e lista de compras ficam num arquivo JSON.
/// No Windows vai para a pasta AppData do usuário (não some sozinha).
class LocalData {
  static File get _file {
    final base = Platform.isWindows
        ? (Platform.environment['APPDATA'] ?? Directory.systemTemp.path)
        : Directory.systemTemp.path;
    return File('$base${Platform.pathSeparator}entre_sabores_data.json');
  }

  static Future<Map<String, dynamic>> read() async {
    try {
      return jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> write(Map<String, dynamic> data) async {
    try {
      await _file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }
}

class EntreSaboresApp extends StatelessWidget {
  const EntreSaboresApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Entre Sabores',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(seedColor: orange, surface: paper),
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          foregroundColor: ink,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          hintStyle: const TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: orange),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(backgroundColor: ink),
      ),
      home: const HomeShell(),
    );
  }
}

/// Tela principal. Fica DENTRO do MaterialApp, por isso o `context` daqui
/// enxerga o Navigator e o ScaffoldMessenger (necessário para abrir telas,
/// diálogos e SnackBars).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final api = RecipeApi();
  final homeSearch = TextEditingController();
  final searchName = TextEditingController();
  final searchIngredients = TextEditingController();
  final shoppingInput = TextEditingController();
  int page = 0;
  bool loading = true;
  String? apiError;
  String? selectedCategory;
  String mode = 'todos';
  List<Recipe> recipes = [];
  List<Recipe> searchResults = [];
  List<dynamic> categories = [];
  Set<String> favoriteIds = {};
  List<Map<String, dynamic>> shoppingItems = [];
  bool searching = false;
  bool searched = false;

  @override
  void initState() {
    super.initState();
    _loadLocal();
    refresh();
  }

  @override
  void dispose() {
    homeSearch.dispose();
    searchName.dispose();
    searchIngredients.dispose();
    shoppingInput.dispose();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    final data = await LocalData.read();
    if (!mounted) return;
    setState(() {
      favoriteIds =
          (data['favorites'] as List? ?? []).map((e) => e.toString()).toSet();
      shoppingItems = (data['shopping'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  }

  Future<void> _saveLocal() => LocalData.write({
        'favorites': favoriteIds.toList(),
        'shopping': shoppingItems,
      });

  Future<void> refresh() async {
    setState(() {
      loading = true;
      apiError = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        api.getRecipes(),
        api.getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        recipes = values[0] as List<Recipe>;
        searchResults = recipes;
        searched = false;
        categories = values[1] as List<dynamic>;
        apiError = null;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        apiError = friendlyError(error);
        loading = false;
      });
    }
  }

  List<String> get categoryNames {
    final names = [
      ...categories.map(
        (e) => e is Map ? (e['nome'] ?? '').toString() : e.toString(),
      ),
      ...fallbackCategories,
    ];
    return names.where((e) => e.isNotEmpty).toSet().toList();
  }

  Future<void> runSearch() async {
    final name = searchName.text.trim();
    final ingredientsText = searchIngredients.text.trim();
    if (name.isEmpty && selectedCategory == null && ingredientsText.isEmpty) {
      setState(() {
        searchResults = recipes;
        searching = false;
        searched = false;
      });
      return;
    }
    setState(() => searching = true);
    try {
      List<Recipe> results;
      if (name.isNotEmpty) {
        results = await api.searchRecipes(name);
        final category = selectedCategory;
        if (category != null) {
          results = results
              .where((r) => r.category.toLowerCase() == category.toLowerCase())
              .toList();
        }
        if (ingredientsText.isNotEmpty) {
          final wanted = ingredientsText
              .split(',')
              .map((e) => e.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList();
          bool has(Recipe r, String q) =>
              r.ingredients.any((i) => i.toLowerCase().contains(q));
          results = results
              .where(
                (r) => mode == 'todos'
                    ? wanted.every((q) => has(r, q))
                    : wanted.any((q) => has(r, q)),
              )
              .toList();
        }
      } else {
        results = await api.getCategoriesRecipes(
          category: selectedCategory,
          ingredients: ingredientsText,
          mode: mode,
        );
      }
      if (!mounted) return;
      setState(() {
        searchResults = results;
        apiError = null;
        searching = false;
        searched = true;
      });
    } catch (error) {
      if (!mounted) return;
      // Algumas APIs respondem 404 quando não acham nada: isso é "sem resultados".
      if (error is ApiException && error.status == 404) {
        setState(() {
          searchResults = [];
          searching = false;
          searched = true;
        });
        return;
      }
      setState(() {
        searchResults = [];
        apiError = friendlyError(error);
        searching = false;
      });
      _snack('Não foi possível buscar. Confira a conexão com a API.');
    }
  }

  Future<void> chooseCategory(String value) async {
    setState(() {
      selectedCategory = value;
      page = 1;
    });
    await runSearch();
  }

  void toggleFavorite(Recipe recipe) {
    setState(() {
      favoriteIds.contains(recipe.id)
          ? favoriteIds.remove(recipe.id)
          : favoriteIds.add(recipe.id);
    });
    _saveLocal();
  }

  void addShopping(String item) {
    if (item.trim().isEmpty ||
        shoppingItems.any(
          (e) =>
              (e['name'] as String).toLowerCase() == item.trim().toLowerCase(),
        )) return;
    setState(() => shoppingItems.add({'name': item.trim(), 'checked': false}));
    _saveLocal();
  }

  void addIngredients(Recipe recipe) {
    for (final ingredient in recipe.ingredients) {
      addShopping(ingredient);
    }
    Navigator.pop(context);
    setState(() => page = 3);
    _snack('Ingredientes adicionados à lista de compras');
  }

  void _snack(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ink,
        ),
      );
  }

  void openRecipe(Recipe recipe) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecipeDetailPage(
            recipe: recipe,
            api: api,
            categories: categoryNames,
            isFavorite: () => favoriteIds.contains(recipe.id),
            onFavorite: () => toggleFavorite(recipe),
            onAdd: addIngredients,
            onEdit: (body) => _updateRecipe(recipe.id, body),
            onDelete: () => _deleteRecipe(recipe),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: IndexedStack(
              index: page,
              sizing: StackFit.expand,
              children: [
                homeView(),
                searchView(),
                favoritesView(),
                shoppingView(),
                profileView(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 67,
        selectedIndex: page,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFFFE9DE),
        onDestinationSelected: (value) => setState(() => page = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favoritos',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag),
            label: 'Compras',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
        toolbarHeight: 62,
        titleSpacing: 18,
        title: const Row(
          children: [
            Icon(Icons.soup_kitchen_rounded, color: orange, size: 29),
            SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ENTRE SABORES',
                  style: TextStyle(
                    color: orange,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                Text(
                  'DELICIOSAS RECEITAS',
                  style:
                      TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: ApiBadge(
                connected: apiError == null && !loading,
                loading: loading,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Perfil',
            onPressed: () => setState(() => page = 4),
            icon: const Icon(Icons.account_circle_outlined, color: orange),
          ),
          const SizedBox(width: 6),
        ],
      );

  Widget homeView() => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(17, 13, 17, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(19),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF4E3D1), Color(0xFFFAF0E7)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BEM-VINDA À SUA COZINHA',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      color: orange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'O que vamos cozinhar\nhoje?',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 28,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ideias gostosas para deixar cada momento especial.',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: homeSearch,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      setState(() {
                        page = 1;
                        searchName.text = homeSearch.text;
                      });
                      runSearch();
                    },
                    decoration: const InputDecoration(
                      hintText: 'Buscar receitas ou ingredientes',
                      prefixIcon: Icon(Icons.search, color: orange),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionTitle(
              title: 'Categorias',
              eyebrow: 'EXPLORE',
              action: 'Ver todas',
              onAction: () => setState(() {
                selectedCategory = null;
                page = 1;
                searchResults = recipes;
              }),
            ),
            SizedBox(
              height: 98,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categoryNames.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) {
                  final name = categoryNames[index];
                  return InkWell(
                    onTap: () => chooseCategory(name),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 124,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            foodIcons[index % foodIcons.length],
                            color: orange,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'serif',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'Explorar →',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle(
                title: 'Receita do dia', eyebrow: 'FEITA PARA VOCÊ'),
            if (loading)
              const LoadingCard()
            else if (recipes.isNotEmpty)
              FeatureRecipeCard(
                recipe: recipes.first,
                onTap: () => openRecipe(recipes.first),
              )
            else
              _emptyWithRetry('Suas receitas do dia vão aparecer aqui.'),
            const SizedBox(height: 19),
            SectionTitle(
              title: 'Mais receitas',
              eyebrow: 'PARA SE INSPIRAR',
              action: 'Ver todas',
              onAction: () {
                setState(() {
                  page = 1;
                  selectedCategory = null;
                  searchResults = recipes;
                });
              },
            ),
            if (loading)
              const LoadingCard()
            else if (recipes.isEmpty)
              _emptyWithRetry('Ainda não há receitas cadastradas.')
            else
              RecipeGrid(
                recipes: recipes.take(6).toList(),
                favorites: favoriteIds,
                onTap: openRecipe,
                onFavorite: toggleFavorite,
              ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewRecipePage(
                    categories: categoryNames,
                    onSubmit: _createRecipe,
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Compartilhar uma receita'),
            ),
          ],
        ),
      );

  Widget searchView() => ListView(
        padding: const EdgeInsets.fromLTRB(17, 15, 17, 24),
        children: [
          const Text(
            'UM MUNDO DE SABORES',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.6,
              color: orange,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Encontre sua próxima\nreceita',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Busque pelo nome ou filtre por categoria e ingredientes.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 17),
          TextField(
            controller: searchName,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => runSearch(),
            decoration: const InputDecoration(
              hintText: 'Ex.: bolo de cenoura',
              prefixIcon: Icon(Icons.search, color: orange),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(selectedCategory),
            initialValue: selectedCategory,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Todas as categorias'),
              ),
              ...categoryNames.map(
                (e) => DropdownMenuItem(value: e, child: Text(e)),
              ),
            ],
            onChanged: (value) => setState(() => selectedCategory = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchIngredients,
            decoration: const InputDecoration(
              labelText: 'Ingredientes',
              hintText: 'Ex.: ovo, farinha',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: mode,
            decoration:
                const InputDecoration(labelText: 'Combinar ingredientes'),
            items: const [
              DropdownMenuItem(value: 'todos', child: Text('Todos')),
              DropdownMenuItem(value: 'qualquer', child: Text('Qualquer um')),
            ],
            onChanged: (value) => setState(() => mode = value ?? 'todos'),
          ),
          const SizedBox(height: 13),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(14),
            ),
            onPressed: searching ? null : runSearch,
            icon: const Icon(Icons.search),
            label: const Text('Encontrar receitas'),
          ),
          const SizedBox(height: 21),
          SectionTitle(
            title: searching ? 'Buscando...' : 'Receitas encontradas',
            eyebrow: 'INSPIRAÇÃO NA MESA',
            action: '${searchResults.length}',
          ),
          const SizedBox(height: 8),
          if (searching)
            const LoadingCard()
          else if (searchResults.isEmpty)
            EmptyState(
              message: apiError ??
                  (searched
                      ? 'Nenhuma receita encontrada. Tente outro nome ou menos filtros.'
                      : 'Use a busca ou os filtros para encontrar receitas.'),
            )
          else
            RecipeGrid(
              recipes: searchResults,
              favorites: favoriteIds,
              onTap: openRecipe,
              onFavorite: toggleFavorite,
            ),
        ],
      );

  Widget favoritesView() {
    final saved = recipes.where((r) => favoriteIds.contains(r.id)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(17, 19, 17, 24),
      children: [
        const Text(
          'SALVOS COM CARINHO',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.6,
            color: orange,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Meu caderno',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Suas receitas favoritas sempre à mão.',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 19),
        if (loading)
          const LoadingCard()
        else if (saved.isEmpty)
          EmptyState(
            message: 'Toque no coração de uma receita para salvá-la aqui.',
          )
        else
          RecipeGrid(
            recipes: saved,
            favorites: favoriteIds,
            onTap: openRecipe,
            onFavorite: toggleFavorite,
          ),
      ],
    );
  }

  Widget shoppingView() => ListView(
        padding: const EdgeInsets.fromLTRB(17, 19, 17, 24),
        children: [
          const Text(
            'TUDO À MÃO',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.6,
              color: orange,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Lista de compras',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Organize os ingredientes para sua próxima aventura.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: shoppingInput,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) {
                    addShopping(value);
                    shoppingInput.clear();
                  },
                  decoration: const InputDecoration(
                    hintText: 'Adicionar ingrediente',
                  ),
                ),
              ),
              const SizedBox(width: 9),
              FilledButton(
                onPressed: () {
                  addShopping(shoppingInput.text);
                  shoppingInput.clear();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 15),
                ),
                child: const Text('Adicionar +'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: const BorderSide(color: line),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 13, 15, 7),
                  child: Row(
                    children: [
                      Text(
                        '${shoppingItems.where((e) => e['checked'] == true).length} de ${shoppingItems.length} itens',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          shoppingItems.clear();
                          _saveLocal();
                        }),
                        child: const Text(
                          'Limpar lista',
                          style: TextStyle(color: orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: line),
                if (shoppingItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(23),
                    child: Text(
                      'Sua lista está vazia. Adicione os ingredientes que faltam.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  )
                else
                  ...shoppingItems.asMap().entries.map(
                        (entry) => CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: orange,
                          title: Text(
                            entry.value['name'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  entry.value['checked'] == true ? muted : ink,
                              decoration: entry.value['checked'] == true
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          value: entry.value['checked'] == true,
                          onChanged: (value) => setState(() {
                            shoppingItems[entry.key]['checked'] =
                                value ?? false;
                            _saveLocal();
                          }),
                          secondary: IconButton(
                            icon:
                                const Icon(Icons.close, color: muted, size: 19),
                            onPressed: () => setState(() {
                              shoppingItems.removeAt(entry.key);
                              _saveLocal();
                            }),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      );

  Widget profileView() => ListView(
        padding: const EdgeInsets.fromLTRB(17, 18, 17, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF6E8D9), paper],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: cream,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.person_outline, color: orange, size: 34),
                ),
                const SizedBox(height: 12),
                const Text(
                  'SEU ESPAÇO',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    color: orange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Olá, cozinheira!',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w700,
                    fontSize: 24,
                  ),
                ),
                const Text(
                  'Seu próximo prato favorito começa por aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stat(value: '${favoriteIds.length}', label: 'Favoritas'),
                    Stat(value: '${recipes.length}', label: 'Receitas'),
                    const Stat(value: '∞', label: 'Sabores'),
                  ],
                ),
                const SizedBox(height: 15),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewRecipePage(
                        categories: categoryNames,
                        onSubmit: _createRecipe,
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Enviar uma receita'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: line),
            ),
            child: Column(
              children: [
                ProfileLink(
                  icon: Icons.favorite_border,
                  label: 'Minhas receitas salvas',
                  onTap: () => setState(() => page = 2),
                ),
                const Divider(height: 1, color: line),
                ProfileLink(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Lista de compras',
                  onTap: () => setState(() => page = 3),
                ),
                const Divider(height: 1, color: line),
                const ProfileLink(
                  icon: Icons.info_outline,
                  label: 'Sobre o Entre Sabores',
                ),
              ],
            ),
          ),
        ],
      );

  Future<void> _createRecipe(Map<String, dynamic> body) async {
    await api.createRecipe(body); // lança erro se a API recusar
    if (!mounted) return;
    await refresh();
    if (!mounted) return;
    setState(() => page = 0);
    _snack('Sua receita foi publicada!');
  }

  Future<void> _updateRecipe(String id, Map<String, dynamic> body) async {
    await api.updateRecipe(id, body);
    if (!mounted) return;
    await refresh();
    _snack('Receita atualizada!');
  }

  Future<void> _deleteRecipe(Recipe recipe) async {
    await api.deleteRecipe(recipe.id);
    favoriteIds.remove(recipe.id); // não deixar favorito órfão
    await _saveLocal();
    if (!mounted) return;
    await refresh();
    _snack('Receita excluída');
  }

  Widget _emptyWithRetry(String fallback) => Column(
        children: [
          EmptyState(message: apiError ?? fallback),
          if (apiError != null)
            TextButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh, color: orange),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(color: orange),
              ),
            ),
        ],
      );
}

class ApiBadge extends StatelessWidget {
  const ApiBadge({super.key, required this.connected, required this.loading});
  final bool connected;
  final bool loading;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 7,
              color: loading
                  ? const Color(0xFFD7AD42)
                  : connected
                      ? const Color(0xFF62A46F)
                      : orange,
            ),
            const SizedBox(width: 5),
            Text(
              loading
                  ? 'Conectando'
                  : connected
                      ? 'Online'
                      : 'Offline',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.eyebrow,
    this.action,
    this.onAction,
  });
  final String title, eyebrow;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    color: orange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                action!,
                style: const TextStyle(color: orange, fontSize: 12),
              ),
            ),
        ],
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line),
        ),
        child: Column(
          children: [
            const Icon(Icons.restaurant_menu, color: orange, size: 27),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      );
}

class LoadingCard extends StatelessWidget {
  const LoadingCard({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(22),
        child: Center(
          child: CircularProgressIndicator(color: orange, strokeWidth: 2),
        ),
      );
}

class FeatureRecipeCard extends StatelessWidget {
  const FeatureRecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
  });
  final Recipe recipe;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 88,
                  height: 95,
                  child: RecipeImage(
                    url: recipe.imageUrl,
                    fallback: Container(
                      color: cream,
                      alignment: Alignment.center,
                      child: const Icon(Icons.ramen_dining,
                          color: orange, size: 43),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ESCOLHA DA CASA',
                      style: TextStyle(
                        color: orange,
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${recipe.timeLabel}  ·  ${recipe.portionsLabel}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${recipe.category}  →',
                      style: const TextStyle(
                        color: orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class RecipeGrid extends StatelessWidget {
  const RecipeGrid({
    super.key,
    required this.recipes,
    required this.favorites,
    required this.onTap,
    required this.onFavorite,
  });
  final List<Recipe> recipes;
  final Set<String> favorites;
  final ValueChanged<Recipe> onTap, onFavorite;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              (constraints.maxWidth / 190).floor().clamp(2, 5).toInt();
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recipes.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 11,
              mainAxisExtent: 235,
            ),
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              final saved = favorites.contains(recipe.id);
              return InkWell(
                onTap: () => onTap(recipe),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RecipeImage(
                              url: recipe.imageUrl,
                              fallback: Container(
                                alignment: Alignment.center,
                                color: [
                                  cream,
                                  const Color(0xFFF2E1D0),
                                  const Color(0xFFF8E8D7),
                                ][index % 3],
                                child: Icon(
                                  foodIcons[index % foodIcons.length],
                                  color: const Color(0xFFC07752),
                                  size: 48,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 7,
                              top: 7,
                              child: Material(
                                color: Colors.white,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: () => onFavorite(recipe),
                                  customBorder: const CircleBorder(),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      saved
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: saved ? orange : muted,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recipe.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'serif',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${recipe.timeLabel} · ${recipe.category}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(color: muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
}

/// Mostra a foto da receita; se não houver foto (ou ela falhar), mostra [fallback].
class RecipeImage extends StatelessWidget {
  const RecipeImage({super.key, required this.url, required this.fallback});
  final String? url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final link = url?.trim() ?? '';
    if (link.isEmpty) return fallback;
    return Image.network(
      link,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              color: cream,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: orange, strokeWidth: 2),
              ),
            ),
      errorBuilder: (context, error, stack) => fallback,
    );
  }
}

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({
    super.key,
    required this.recipe,
    required this.api,
    required this.categories,
    required this.isFavorite,
    required this.onFavorite,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });
  final Recipe recipe;
  final RecipeApi api;
  final List<String> categories;
  final bool Function() isFavorite;
  final VoidCallback onFavorite;
  final void Function(Recipe) onAdd;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function() onDelete;
  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late Recipe recipe = widget.recipe;
  late bool saved = widget.isFavorite();
  bool loading = fetchDetailsFromApi;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!fetchDetailsFromApi) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final fresh = await widget.api.getRecipe(widget.recipe.id);
      if (!mounted) return;
      setState(() {
        recipe = fresh;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = friendlyError(e);
        loading = false;
      });
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewRecipePage(
          categories: widget.categories,
          initial: recipe,
          onSubmit: widget.onEdit,
        ),
      ),
    );
    if (!mounted || changed != true) return;
    if (fetchDetailsFromApi) {
      _load();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir receita?'),
        content: Text('"${recipe.name}" será removida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.onDelete();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _info(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: orange),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: muted, fontSize: 13)),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            recipe.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'serif',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          actions: [
            IconButton(
              tooltip: saved ? 'Remover dos favoritos' : 'Favoritar',
              icon: Icon(
                saved ? Icons.favorite : Icons.favorite_border,
                color: orange,
              ),
              onPressed: () {
                widget.onFavorite();
                setState(() => saved = widget.isFavorite());
              },
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _edit();
                if (value == 'delete') _confirmDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      color: orange,
                      backgroundColor: cream,
                    ),
                  ),
                if (error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE3E3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(error!,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Tentar de novo'),
                        ),
                      ],
                    ),
                  ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: SizedBox(
                    height: 190,
                    child: RecipeImage(
                      url: recipe.imageUrl,
                      fallback: Container(
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cream, Color(0xFFF1DCC7)],
                          ),
                        ),
                        child: const Icon(
                          Icons.soup_kitchen,
                          size: 76,
                          color: orange,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  recipe.category.toUpperCase(),
                  style: const TextStyle(
                    color: orange,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  recipe.name,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 18,
                  runSpacing: 4,
                  children: [
                    _info(Icons.schedule, recipe.timeLabel),
                    _info(Icons.restaurant, recipe.portionsLabel),
                  ],
                ),
                _heading('Ingredientes'),
                if (recipe.ingredients.isEmpty)
                  const Text(
                    'Ingredientes não informados.',
                    style: TextStyle(color: muted, fontSize: 13),
                  )
                else
                  ...recipe.ingredients.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.check_box_outline_blank,
                              size: 18,
                              color: orange,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(item,
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),
                _heading('Modo de preparo'),
                Text(
                  recipe.hasSteps
                      ? recipe.steps
                      : 'Modo de preparo não informado.',
                  style:
                      const TextStyle(fontSize: 14, height: 1.6, color: muted),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: recipe.ingredients.isEmpty
                      ? null
                      : () => widget.onAdd(recipe),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  style: FilledButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(14),
                  ),
                  label: const Text('Adicionar ingredientes à lista'),
                ),
              ],
            ),
          ),
        ),
      );
}

class NewRecipePage extends StatefulWidget {
  const NewRecipePage({
    super.key,
    required this.categories,
    required this.onSubmit,
    this.initial,
  });
  final List<String> categories;
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  final Recipe? initial; // preenchido = modo edição
  @override
  State<NewRecipePage> createState() => _NewRecipePageState();
}

class _NewRecipePageState extends State<NewRecipePage> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(),
      minutes = TextEditingController(),
      portions = TextEditingController(),
      ingredients = TextEditingController(),
      steps = TextEditingController(),
      image = TextEditingController();
  String? category;
  bool saving = false;
  String? error;

  bool get editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    if (r != null) {
      name.text = r.name;
      minutes.text = r.hasTime ? r.minutes : '';
      portions.text = r.hasPortions ? r.portions : '';
      ingredients.text = r.ingredients.join('\n');
      steps.text = r.steps;
      image.text = r.imageUrl ?? '';
      category = widget.categories.contains(r.category) ? r.category : null;
    }
  }

  @override
  void dispose() {
    name.dispose();
    minutes.dispose();
    portions.dispose();
    ingredients.dispose();
    steps.dispose();
    image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            editing ? 'Editar receita' : 'Nova receita',
            style: const TextStyle(
              fontFamily: 'serif',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(17, 8, 17, 24),
                children: [
                  Text(
                    editing ? 'AJUSTE SUA RECEITA' : 'FEITA POR VOCÊ',
                    style: const TextStyle(
                      color: orange,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    editing
                        ? 'Altere o que precisar e salve.'
                        : 'Compartilhe sua receita favorita.',
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  _field(
                    name,
                    'Nome da receita',
                    'Ex.: Bolo de cenoura',
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category ??
                        (widget.categories.isNotEmpty
                            ? widget.categories.first
                            : null),
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: widget.categories
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (value) => category = value,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child:
                            _field(minutes, 'Tempo (min)', '40', number: true),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(portions, 'Porções', '4', number: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    ingredients,
                    'Ingredientes (um por linha)',
                    '2 ovos\n1 xícara de farinha',
                    required: true,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    steps,
                    'Modo de preparo',
                    'Conte como preparar, passo a passo...',
                    required: true,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    image,
                    'Link da foto (opcional)',
                    'https://...',
                    url: true,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        error!,
                        style: const TextStyle(color: orange, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(15),
                    ),
                    child: Text(
                      saving
                          ? (editing ? 'Salvando...' : 'Publicando...')
                          : (editing
                              ? 'Salvar alterações'
                              : 'Publicar receita'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool required = false,
    bool number = false,
    bool url = false,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: number
            ? TextInputType.number
            : (url ? TextInputType.url : TextInputType.text),
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (required && text.isEmpty) return 'Preencha este campo';
          if (number && (int.tryParse(text) ?? 0) <= 0) {
            return 'Informe um número maior que zero';
          }
          if (url && text.isNotEmpty && !text.startsWith('http')) {
            return 'Use um link que comece com http:// ou https://';
          }
          return null;
        },
      );

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    final body = <String, dynamic>{
      'nome': name.text.trim(),
      'categoria': category ??
          (widget.categories.isNotEmpty
              ? widget.categories.first
              : 'Receita da casa'),
      'tempoPreparo': int.parse(minutes.text.trim()),
      'porcoes': int.parse(portions.text.trim()),
      'ingredientes': ingredients.text
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'modoPreparo': steps.text.trim(),
    };
    final photo = image.text.trim();
    if (photo.isNotEmpty || (editing && widget.initial!.imageUrl != null)) {
      body['imagem_url'] = photo;
    }
    try {
      await widget.onSubmit(body);
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = friendlyError(exception);
      });
    }
  }
}

class Stat extends StatelessWidget {
  const Stat({super.key, required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 85,
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'serif',
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      );
}

class ProfileLink extends StatelessWidget {
  const ProfileLink({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon, color: orange, size: 19),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        trailing: const Icon(Icons.chevron_right, color: muted),
        onTap: onTap,
      );
}
