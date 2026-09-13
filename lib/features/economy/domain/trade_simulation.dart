/// A small, deterministic trade simulation over the Economy network.
///
/// The network — cities, routes, nodes and who works them — is the saved
/// World. The run itself is not: workers, cargo and stockpiles exist only
/// while the Simulate tab is playing, and pressing reset rebuilds them from
/// the saved network.
library;

import 'dart:ui';

/// A worker's repeated journey between its city and one resource node.
class SimulationNodeRun {
  const SimulationNodeRun({
    required this.id,
    required this.cityId,
    required this.city,
    required this.node,
    required this.resourceId,
    this.workers = 1,
  });

  final String id;
  final String cityId;
  final Offset city;
  final Offset node;
  final String resourceId;
  final int workers;
}

/// One direction of a trade route: cargo leaves [startCityId] and is
/// delivered to [endCityId], then the trader turns around.
class SimulationRouteRun {
  const SimulationRouteRun({
    required this.id,
    required this.startCityId,
    required this.endCityId,
    required this.from,
    required this.to,
    required this.controls,
    required this.resourceId,
    this.traders = 1,
  });

  final String id;
  final String startCityId;
  final String endCityId;
  final Offset from;
  final Offset to;
  final List<Offset> controls;
  final String resourceId;
  final int traders;
}

/// One animated thing on the map.
class SimulationAgent {
  SimulationAgent({
    required this.id,
    required this.from,
    required this.to,
    required this.controls,
    required this.resourceId,
    this.cityAtStart,
    this.cityAtEnd,
    this.duration = const Duration(seconds: 5),
    double phase = 0,
  }) : t = phase.clamp(0.0, 1.0);

  final String id;
  final Offset from;
  final Offset to;
  final List<Offset> controls;
  final String resourceId;

  /// Where cargo is delivered when the agent arrives at that end, if anywhere.
  final String? cityAtStart;
  final String? cityAtEnd;

  final Duration duration;

  /// Position along the journey, 0 at [from] and 1 at [to].
  double t;
  int direction = 1;

  /// Where the agent is right now, in map UV space.
  Offset get position {
    if (controls.length < 2) {
      return Offset.lerp(from, to, t)!;
    }
    final mt = 1 - t;
    return from * (mt * mt * mt) +
        controls[0] * (3 * mt * mt * t) +
        controls[1] * (3 * mt * t * t) +
        to * (t * t * t);
  }
}

class TradeSimulation {
  TradeSimulation({
    List<SimulationNodeRun> nodeRuns = const [],
    List<SimulationRouteRun> routes = const [],
  }) {
    for (final run in nodeRuns) {
      for (var i = 0; i < run.workers; i++) {
        agents.add(
          SimulationAgent(
            id: '${run.id}-worker-$i',
            from: run.city,
            to: run.node,
            controls: const [],
            resourceId: run.resourceId,
            cityAtStart: run.cityId,
            duration: const Duration(milliseconds: 3500),
            phase: run.workers == 0 ? 0 : (i / run.workers) * 0.9,
          ),
        );
      }
    }
    for (final route in routes) {
      for (var i = 0; i < route.traders; i++) {
        agents.add(
          SimulationAgent(
            id: '${route.id}-trader-$i',
            from: route.from,
            to: route.to,
            controls: route.controls,
            resourceId: route.resourceId,
            cityAtStart: route.startCityId,
            cityAtEnd: route.endCityId,
            phase: route.traders == 0 ? 0 : (i / route.traders) * 0.9,
          ),
        );
      }
    }
  }

  final List<SimulationAgent> agents = [];

  /// What each city has received so far, by city id and resource id.
  final Map<String, Map<String, int>> stockpiles = {};

  /// How many deliveries have landed.
  int deliveries = 0;

  void advance(double seconds) {
    if (seconds <= 0) return;
    for (final agent in agents) {
      agent.t +=
          agent.direction * seconds / (agent.duration.inMicroseconds / 1e6);
      if (agent.t >= 1 && agent.direction > 0) {
        agent.t = 1;
        _deliver(agent, agent.cityAtEnd);
        agent.direction = -1;
      } else if (agent.t <= 0 && agent.direction < 0) {
        agent.t = 0;
        _deliver(agent, agent.cityAtStart);
        agent.direction = 1;
      }
    }
  }

  void _deliver(SimulationAgent agent, String? cityId) {
    if (cityId == null) return;
    final city = stockpiles.putIfAbsent(cityId, () => {});
    city[agent.resourceId] = (city[agent.resourceId] ?? 0) + 1;
    deliveries++;
  }
}
