import 'package:flutter/material.dart';

import 'build_info.dart';

const _env = String.fromEnvironment('ENV', defaultValue: 'dev');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_ci_tools example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Example ($_env)')),
      body: IndexedStack(
        index: _tab,
        children: const [CounterPage(), AboutPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add), label: 'Counter'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: 'About'),
        ],
      ),
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('You have pushed the button this many times:'),
          Text('$_count', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => setState(() => _count++),
            icon: const Icon(Icons.add),
            label: const Text('Increment'),
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BuildInfo>(
      future: BuildInfo.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'build_info.json not populated — '
                'run `dart run ci/build.dart <env>` first.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final info = snapshot.data!;
        return ListView(
          children: [
            _row('env', info.env),
            _row('buildName', info.buildName),
            _row('buildNumber', info.buildNumber.toString()),
            _row('gitHash', info.gitHash),
            _row('branch', info.branch),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('recent commits',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(info.recentCommits,
                  style: const TextStyle(fontFamily: 'monospace')),
            ),
          ],
        );
      },
    );
  }

  Widget _row(String label, String value) => ListTile(
        title: Text(label),
        subtitle: Text(value, style: const TextStyle(fontFamily: 'monospace')),
        dense: true,
      );
}
