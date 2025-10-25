import SwiftUI
import CoreMotion

struct Game {
    enum Direction {
        case up, down, left, right
    }

    struct Position: Hashable, Equatable {
        var column: Int
        var row: Int
    }

    struct Tile: Identifiable, Equatable {
        var id = UUID()
        var value: Int
        var position: Position
    }

    var score = 0
    var tiles = [Tile]()

    mutating func reset() {
        tiles = []

        var positions = Set<Position>()
        while tiles.count < 2 {
            let position = Position(column: Int.random(in: 0..<4), row: Int.random(in: 0..<4))
            guard !positions.contains(position) else { continue }

            positions.insert(position)
            tiles.append(Tile(value: newTileValue(), position: position))
        }

        score = 0
    }

    private func newTileValue() -> Int {
        Int.random(in: 0..<8) == 0 ? 4 : 2
    }

    func tile(atPosition position: Position) -> Tile? {
        tiles.first(where: { $0.position == position })
    }

    mutating func append(tile: Tile) {
        tiles.append(tile)
    }

    private mutating func doMove(
        position positionFunc: (Int, Int) -> Position,
        reverse axisFunc: (Position) -> (Int, Int)
    ) -> Tile? {
        var moved = false
        var tiles = [Tile]()

        var freeSpaces = Set((0..<4).flatMap { column in
            (0..<4).map { row in
                Position(column: column, row: row)
            }
        })

        for crossAxis in 0..<4 {
            var skylineTileIndex: Int? = nil

            for axis in 0..<4 {
                let position = positionFunc(axis, crossAxis)

                guard let prevTile = tile(atPosition: position) else {
                    continue
                }

                let skylineTile: Tile? = if let skylineTileIndex {
                    tiles[skylineTileIndex]
                } else {
                    nil
                }

                let nextAxis: Int = if let skylineTile {
                    axisFunc(skylineTile.position).0 + 1
                } else {
                    0
                }

                let nextPosition = positionFunc(nextAxis, crossAxis)

                let nextTile: Tile
                if let skylineTile,
                   skylineTile.value == prevTile.value {
                    moved = true
                    tiles.remove(at: skylineTileIndex!)

                    nextTile = Tile(
                        id: prevTile.id,
                        value: skylineTile.value * 2,
                        position: skylineTile.position
                    )

                    score += skylineTile.value * 2
                } else {
                    moved = moved || prevTile.position != nextPosition

                    nextTile = Tile(
                        id: prevTile.id,
                        value: prevTile.value,
                        position: nextPosition
                    )
                }

                skylineTileIndex = tiles.count

                tiles.append(nextTile)
                freeSpaces.remove(nextTile.position)
            }
        }

        guard moved else { return nil }

        self.tiles = tiles

        if let position = Array(freeSpaces).shuffled().first {
            return Tile(value: newTileValue(), position: position)
        } else {
            return nil
        }
    }

    mutating func move(direction: Direction) -> Tile? {
        switch direction {
        case .up:
            doMove { (axis, crossAxis) in
                Position(column: crossAxis, row: axis)
            } reverse: { position in
                (position.row, position.column)
            }
        case .down:
            doMove { (axis, crossAxis) in
                Position(column: crossAxis, row: 3 - axis)
            } reverse: { position in
                (3 - position.row, position.column)
            }
        case .left:
            doMove { (axis, crossAxis) in
                Position(column: axis, row: crossAxis)
            } reverse: { position in
                (position.column, position.row)
            }
        case .right:
            doMove { (axis, crossAxis) in
                Position(column: 3 - axis, row: crossAxis)
            } reverse: { position in
                (3 - position.column, position.row)
            }
        }
    }
}

@Observable
class MotionManager {
    private var manager = CMMotionManager()
    var x: Double = 0
    var y: Double = 0

    init() {
        manager.deviceMotionUpdateInterval = 1 / 60
    }

    func beginUpdates() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.x = motion.attitude.roll
            self.y = motion.attitude.pitch
        }
    }

    func stopUpdates() {
        manager.stopDeviceMotionUpdates()
    }
}

struct ContentView: View {
    @State var game = Game()
    @State private var motion = MotionManager()
    @Namespace var namespace

    private let gap = CGFloat(8)

    var gesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { gesture in
                let spread: Double = 30
                let angle: Angle = .radians(atan2(gesture.translation.height, gesture.translation.width))

                let direction: Game.Direction? = switch angle {
                case (.degrees(-spread))...(.degrees(spread)): .right
                case (.degrees(90 - spread)...(.degrees(90 + spread))): .down
                case (.degrees(180 - spread)...(.degrees(180))): .left
                case (.degrees(-180))...(.degrees(-(180 - spread))): .left
                case (.degrees(-(90 + spread))...(.degrees(-(90 - spread)))): .up
                default: nil
                }

                guard let direction else { return }

                var newTile: Game.Tile?
                withAnimation(.easeOut(duration: 0.15)) {
                    newTile = game.move(direction: direction)
                }

                withAnimation(.linear(duration: 0.2).delay(0.10)) {
                    guard let newTile else { return }
                    game.append(tile: newTile)
                }
            }
    }

    @ViewBuilder func tile(_ tile: Game.Tile, size: CGFloat) -> some View {
        let x = CGFloat(tile.position.column) * (size + gap)
        let y = CGFloat(tile.position.row) * (size + gap)

        GlassEffectContainer {
            Text(tile.value, format: .number)
                .minimumScaleFactor(0.5)
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 4)
                .contentTransition(.numericText(value: Double(tile.value)))
                .padding(4)
                .frame(width: size, height: size)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24))
                .glassEffectTransition(.materialize)
                .glassEffectID(tile.id, in: namespace)
                .offset(x: x, y: y)
        }
    }

    @ViewBuilder
    var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(height: 1)
    }

    var body: some View {
        VStack {
            HStack {
                Text("Score: \(game.score)")
                    .contentTransition(.numericText(value: Double(game.score)))

                Spacer()

                Button("Reset") {
                    withAnimation {
                        game.reset()
                    }
                }
            }
            .font(.system(size: 24, weight: .black, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(.white)

            Spacer()

            divider

            GeometryReader { proxy in
                let dimension = min(proxy.size.width, proxy.size.height)
                let size = floor((dimension - 3 * gap) / 4)

                ZStack {
                    ForEach(game.tiles, id: \.id) { t in
                        tile(t, size: size)
                    }
                }
                .frame(width: dimension, height: dimension, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .gesture(gesture)

            divider

            Spacer()
        }
        .padding()
        .background {
            Image("Volcano")
                .resizable()
                .scaledToFill()
                .padding(-40)
                .offset(x: motion.x * -20, y: motion.y * 20)
                .ignoresSafeArea()
        }
        .onAppear {
            game.reset()
            motion.beginUpdates()
        }
    }
}

#Preview {
    ContentView()
}
