import 'package:dayseven/features/economy/domain/trade_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a trader delivers at the far city and turns around', () {
    final simulation = TradeSimulation(
      routes: const [
        SimulationRouteRun(
          id: 'r1',
          startCityId: 'aldenmoor',
          endCityId: 'oakhaven',
          from: Offset(0, 0),
          to: Offset(1, 0),
          controls: [],
          resourceId: 'stone',
        ),
      ],
    );

    expect(simulation.agents, hasLength(1));
    simulation.advance(5);
    expect(simulation.stockpiles['oakhaven']?['stone'], 1);

    simulation.advance(5);
    expect(simulation.stockpiles['aldenmoor']?['stone'], 1);
    expect(simulation.deliveries, 2);
  });

  test('a worker collects at the node and delivers at home, not at the node',
      () {
    final simulation = TradeSimulation(
      nodeRuns: const [
        SimulationNodeRun(
          id: 'n1',
          cityId: 'aldenmoor',
          city: Offset(0, 0),
          node: Offset(1, 0),
          resourceId: 'timber',
        ),
      ],
    );

    simulation.advance(3.5);
    expect(simulation.stockpiles, isEmpty, reason: 'arrival at a node is not a delivery');

    simulation.advance(3.5);
    expect(simulation.stockpiles['aldenmoor']?['timber'], 1);
  });

  test('an agent follows the curve it was given', () {
    final agent = SimulationAgent(
      id: 'a',
      from: const Offset(0, 0),
      to: const Offset(1, 0),
      controls: const [Offset(0.33, -1), Offset(0.66, -1)],
      resourceId: 'gold',
    )..t = 0.5;

    // The curve bends north of the straight line between the endpoints.
    expect(agent.position.dx, closeTo(0.5, 0.01));
    expect(agent.position.dy, lessThan(0));
  });

  test('several workers spread out rather than stepping together', () {
    final simulation = TradeSimulation(
      nodeRuns: const [
        SimulationNodeRun(
          id: 'n1',
          cityId: 'city',
          city: Offset(0, 0),
          node: Offset(1, 0),
          resourceId: 'stone',
          workers: 3,
        ),
      ],
    );

    expect(simulation.agents, hasLength(3));
    expect(simulation.agents.map((agent) => agent.t).toSet(), hasLength(3));
  });
}
