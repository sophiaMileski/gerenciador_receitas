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

void main() => runApp(const EntreSaboresApp());

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.minutes,
    required this.portions,
    required this.ingredients,
    required this.steps,
  });
  final String id;
  final String name;
  final String category;
  final String minutes;
  final String portions;
  final List<String> ingredients;
  final String steps;

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
        ? rawIngredients.map((item) => item.toString()).toList()
        : <String>[];
    return Recipe(
      id: (json['id'] ?? json['nome'] ?? '').toString(),
      name: (json['nome'] ?? json['name'] ?? 'Receita sem nome').toString(),
      category:
          (json['categoria_nome'] ??
                  json['categoria'] ??
                  json['category'] ??
                  'Receita da casa')
              .toString(),
      minutes:
          (json['tempo_preparo'] ??
                  json['tempoPreparo'] ??
                  json['tempo'] ??
                  '—')
              .toString(),
      portions: (json['porcoes'] ?? json['rendimento'] ?? '—').toString(),
      ingredients: list,
      steps:
          (json['modo_preparo'] ??
                  json['modoPreparo'] ??
                  json['preparo'] ??
                  'Prepare com carinho e aproveite.')
              .toString(),
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
    try {
      data = jsonDecode(text);
    } catch (_) {
      data = <String, dynamic>{'mensagem': 'Resposta inválida da API.'};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data is Map
            ? data['mensagem'] ?? 'A API retornou ${response.statusCode}.'
            : 'A API retornou ${response.statusCode}.',
      );
    }
    return data;
  }

  Future<List<Recipe>> getRecipes() async =>
      _asRecipes(await request('/receitas'));
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

  Future<Recipe> createRecipe(Map<String, dynamic> body) async {
    final data = await request('/receitas', method: 'POST', body: body);
    return Recipe.fromJson(
      (data is Map && data['receita'] is Map ? data['receita'] : data)
          as Map<String, dynamic>,
    );
  }

  List<Recipe> _asRecipes(dynamic value) => value is List
      ? value.whereType<Map<String, dynamic>>().map(Recipe.fromJson).toList()
      : <Recipe>[];
}

class LocalData {
  static final File _file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}entre_sabores_data.json',
  );
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

class EntreSaboresApp extends StatefulWidget {
  const EntreSaboresApp({super.key});
  @override
  State<EntreSaboresApp> createState() => _EntreSaboresAppState();
}

class _EntreSaboresAppState extends State<EntreSaboresApp> {
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
      favoriteIds = (data['favorites'] as List? ?? [])
          .map((e) => e.toString())
          .toSet();
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
        categories = values[1] as List<dynamic>;
        apiError = null;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        apiError = error.toString().replaceFirst('Exception: ', '');
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
    if (searchName.text.trim().isEmpty &&
        selectedCategory == null &&
        searchIngredients.text.trim().isEmpty) {
      setState(() {
        searchResults = recipes;
        searching = false;
      });
      return;
    }
    setState(() => searching = true);
    try {
      List<Recipe> results;
      if (searchName.text.trim().isNotEmpty) {
        results = await api.searchRecipes(searchName.text.trim());
        if (selectedCategory != null)
          results = results
              .where(
                (r) =>
                    r.category.toLowerCase() == selectedCategory!.toLowerCase(),
              )
              .toList();
        if (searchIngredients.text.trim().isNotEmpty) {
          final ingredients = searchIngredients.text
              .split(',')
              .map((e) => e.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList();
          results = results.where((r) {
            if (mode == 'todos')
              return ingredients.every(
                (q) => r.ingredients.any((i) => i.toLowerCase().contains(q)),
              );
            return ingredients.any(
              (q) => r.ingredients.any((i) => i.toLowerCase().contains(q)),
            );
          }).toList();
        }
      } else {
        results = await api.getCategoriesRecipes(
          category: selectedCategory,
          ingredients: searchIngredients.text.trim(),
          mode: mode,
        );
      }
      if (!mounted) return;
      setState(() {
        searchResults = results;
        apiError = null;
        searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        searchResults = [];
        apiError = error.toString().replaceFirst('Exception: ', '');
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
        ))
      return;
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

  void openRecipe(Recipe recipe) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paper,
    builder: (_) => RecipeDetails(
      recipe: recipe,
      saved: favoriteIds.contains(recipe.id),
      onFavorite: () => toggleFavorite(recipe),
      onAdd: () => addIngredients(recipe),
    ),
  );

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
      home: Scaffold(
        appBar: _appBar(),
        body: SafeArea(
          top: false,
          child: IndexedStack(
            index: page,
            children: [
              homeView(),
              searchView(),
              favoritesView(),
              shoppingView(),
              profileView(),
            ],
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
              style: TextStyle(color: muted, fontSize: 8, letterSpacing: 1.5),
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
                  fontSize: 9,
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
                style: TextStyle(color: muted, fontSize: 12),
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
          height: 91,
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
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text(
                        'Explorar →',
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Receita do dia', eyebrow: 'FEITA PARA VOCÊ'),
        if (loading)
          const LoadingCard()
        else if (recipes.isNotEmpty)
          FeatureRecipeCard(
            recipe: recipes.first,
            onTap: () => openRecipe(recipes.first),
          )
        else
          EmptyState(
            message: apiError ?? 'Suas receitas do dia vão aparecer aqui.',
          ),
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
          EmptyState(message: apiError ?? 'Ainda não há receitas cadastradas.')
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
          fontSize: 9,
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
        style: TextStyle(color: muted, fontSize: 12),
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
        decoration: const InputDecoration(labelText: 'Combinar ingredientes'),
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
          message:
              apiError ?? 'Use a busca ou os filtros para encontrar receitas.',
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
            fontSize: 9,
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
          style: TextStyle(color: muted, fontSize: 12),
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
          fontSize: 9,
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
        style: TextStyle(color: muted, fontSize: 12),
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
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 15),
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
                      fontSize: 12,
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
                      style: TextStyle(color: orange, fontSize: 11),
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
                  style: TextStyle(color: muted, fontSize: 12),
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
                      color: entry.value['checked'] == true ? muted : ink,
                      decoration: entry.value['checked'] == true
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  value: entry.value['checked'] == true,
                  onChanged: (value) => setState(() {
                    shoppingItems[entry.key]['checked'] = value ?? false;
                    _saveLocal();
                  }),
                  secondary: IconButton(
                    icon: const Icon(Icons.close, color: muted, size: 19),
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
              child: const Icon(Icons.person_outline, color: orange, size: 34),
            ),
            const SizedBox(height: 12),
            const Text(
              'SEU ESPAÇO',
              style: TextStyle(
                fontSize: 9,
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
              style: TextStyle(color: muted, fontSize: 12),
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
    final recipe = await api.createRecipe(body);
    if (!mounted) return;
    setState(() {
      recipes.insert(0, recipe);
      page = 0;
    });
    Navigator.pop(context);
    _snack('Sua receita foi publicada!');
  }
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
          style: const TextStyle(color: muted, fontSize: 9),
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
                fontSize: 9,
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
            style: const TextStyle(color: orange, fontSize: 11),
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
          style: const TextStyle(color: muted, fontSize: 11),
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
          Container(
            width: 88,
            height: 95,
            decoration: BoxDecoration(
              color: cream,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.ramen_dining, color: orange, size: 43),
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
                    fontSize: 8,
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
                  '${recipe.minutes} min  ·  ${recipe.portions} porções',
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
                const SizedBox(height: 7),
                Text(
                  '${recipe.category}  →',
                  style: const TextStyle(
                    color: orange,
                    fontSize: 10,
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
      final columns = constraints.maxWidth > 500 ? 3 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: recipes.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 11,
          childAspectRatio: .84,
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
                        Container(
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
                            fontSize: 12,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${recipe.minutes} min · ${recipe.category}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 9),
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

class RecipeDetails extends StatelessWidget {
  const RecipeDetails({
    super.key,
    required this.recipe,
    required this.saved,
    required this.onFavorite,
    required this.onAdd,
  });
  final Recipe recipe;
  final bool saved;
  final VoidCallback onFavorite, onAdd;
  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .86,
    minChildSize: .55,
    maxChildSize: .95,
    builder: (context, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(height: 13),
        Container(
          height: 170,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [cream, Color(0xFFF1DCC7)]),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(Icons.soup_kitchen, size: 76, color: orange),
        ),
        const SizedBox(height: 15),
        Text(
          recipe.category.toUpperCase(),
          style: const TextStyle(
            color: orange,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          recipe.name,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 25,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '◷ ${recipe.minutes} min     ♧ ${recipe.portions} porções',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 17),
        const Text(
          'Ingredientes',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        ...recipe.ingredients.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                const Icon(
                  Icons.check_box_outline_blank,
                  size: 17,
                  color: orange,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(item, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Modo de preparo',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          recipe.steps,
          style: const TextStyle(fontSize: 12, height: 1.6, color: muted),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.shopping_bag_outlined),
                style: FilledButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(13),
                ),
                label: const Text('Adicionar ingredientes'),
              ),
            ),
            IconButton(
              onPressed: onFavorite,
              icon: Icon(
                saved ? Icons.favorite : Icons.favorite_border,
                color: orange,
                size: 25,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class NewRecipePage extends StatefulWidget {
  const NewRecipePage({
    super.key,
    required this.categories,
    required this.onSubmit,
  });
  final List<String> categories;
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  @override
  State<NewRecipePage> createState() => _NewRecipePageState();
}

class _NewRecipePageState extends State<NewRecipePage> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(),
      minutes = TextEditingController(),
      portions = TextEditingController(),
      ingredients = TextEditingController(),
      steps = TextEditingController();
  String? category;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    minutes.dispose();
    portions.dispose();
    ingredients.dispose();
    steps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Nova receita',
        style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w700),
      ),
    ),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(17, 8, 17, 24),
        children: [
          const Text(
            'FEITA POR VOCÊ',
            style: TextStyle(
              color: orange,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Compartilhe sua receita favorita.',
            style: TextStyle(color: muted, fontSize: 12),
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
            initialValue:
                category ??
                (widget.categories.isNotEmpty ? widget.categories.first : null),
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
                child: _field(minutes, 'Tempo (min)', '40', number: true),
              ),
              const SizedBox(width: 10),
              Expanded(child: _field(portions, 'Porções', '4', number: true)),
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
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                error!,
                style: const TextStyle(color: orange, fontSize: 11),
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
            child: Text(saving ? 'Publicando...' : 'Publicar receita'),
          ),
        ],
      ),
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool required = false,
    bool number = false,
    int maxLines = 1,
  }) => TextFormField(
    controller: controller,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    maxLines: maxLines,
    decoration: InputDecoration(labelText: label, hintText: hint),
    validator: (value) {
      if (required && (value == null || value.trim().isEmpty))
        return 'Preencha este campo';
      if (number && (int.tryParse(value ?? '') ?? 0) <= 0)
        return 'Informe um número maior que zero';
      return null;
    },
  );
  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSubmit({
        'nome': name.text.trim(),
        'categoria':
            category ??
            (widget.categories.isNotEmpty
                ? widget.categories.first
                : 'Receita da casa'),
        'tempoPreparo': int.parse(minutes.text),
        'porcoes': int.parse(portions.text),
        'ingredientes': ingredients.text
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'modoPreparo': steps.text.trim(),
      });
    } catch (exception) {
      setState(() {
        saving = false;
        error = 'Não foi possível publicar. Confira se a API está conectada.';
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
        Text(label, style: const TextStyle(fontSize: 9, color: muted)),
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
    title: Text(label, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, color: muted),
    onTap: onTap,
  );
}
