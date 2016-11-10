import core.sys.windows.windows;
import std.string;
import std.random;
import std.datetime;
import std.algorithm;
import std.process : execute;
import std.json;
import fs = std.file;

enum StartLevel = 10;
enum HoldThreshold = 6;
// version = AutoPlay;

__gshared
{
	HANDLE wHnd;
	HANDLE rHnd;
	CHAR_INFO white, gray, black, hDivider, vDivider, dividerCross;
	CHAR_INFO[8] tetrominoColor;
}

enum Width = 20;
enum Height = 20;
	
enum VirtualWidth = 10;
enum VirtualHeight = 24;
enum FieldOffsetY = Height - VirtualHeight - 1;

enum Tetromino : ubyte
{
	I, L, J, T, S, Z, O, None
}

static immutable ubyte[][][] rotations = [
	// Tetromino.I
	[[0,0,0,0, 0,0,1,0, 0,0,0,0, 0,1,0,0],
	 [1,1,1,1, 0,0,1,0, 0,0,0,0, 0,1,0,0],
	 [0,0,0,0, 0,0,1,0, 1,1,1,1, 0,1,0,0],
	 [0,0,0,0, 0,0,1,0, 0,0,0,0, 0,1,0,0]],
	 // Tetromino.L
	[[0,0,1, 0,1,0, 0,0,0, 1,1,0],
	 [1,1,1, 0,1,0, 1,1,1, 0,1,0],
	 [0,0,0, 0,1,1, 1,0,0, 0,1,0]],
	 // Tetromino.J
	[[1,0,0, 0,1,1, 0,0,0, 0,1,0],
	 [1,1,1, 0,1,0, 1,1,1, 0,1,0],
	 [0,0,0, 0,1,0, 0,0,1, 1,1,0]],
	 // Tetromino.T
	[[0,1,0, 0,1,0, 0,0,0, 0,1,0],
	 [1,1,1, 0,1,1, 1,1,1, 1,1,0],
	 [0,0,0, 0,1,0, 0,1,0, 0,1,0]],
	 // Tetromino.S
	[[0,1,1, 0,1,0, 0,0,0, 1,0,0],
	 [1,1,0, 0,1,1, 0,1,1, 1,1,0],
	 [0,0,0, 0,0,1, 1,1,0, 0,1,0]],
	 // Tetromino.Z
	[[1,1,0, 0,0,1, 0,0,0, 0,1,0],
	 [0,1,1, 0,1,1, 1,1,0, 1,1,0],
	 [0,0,0, 0,1,0, 0,1,1, 1,0,0]],
	 // Tetromino.O
	[[1,1, 1,1, 1,1, 1,1],
	 [1,1, 1,1, 1,1, 1,1]],
	 // None
	[[0]],
];

struct Game
{
	void start()
	{
		foreach (ref line; field)
			line[] = 0;
		gameover = false;
		held = false;
		heldTetromino = Tetromino.None;
		updateTimer.reset();
		updateTimer.start();
		refreshTetrominos();
		nextTetromino();
	}

	void update()
	{
		if (updateTimer.peek.to!("msecs", int) > tickTime)
		{
			updateTimer.reset();
			updateTimer.start();
			refreshTetrominos();
			if (!collides(currentTetromino, currentRotation, currentPosition[0], currentPosition[1] + 1))
				currentPosition[1]++;
			else if (!placeTimerActive)
			{
				placeTimerActive = true;
				placeTimer.reset();
				placeTimer.start();
			}
			else
				tryPlace();
		}
	}
	
	void moveLeft()
	{
		if (collides(currentTetromino, currentRotation, currentPosition[0] - 1, currentPosition[1]))
			return;
		currentPosition[0]--;
		resetTimer();
	}
	
	void moveRight()
	{
		if (collides(currentTetromino, currentRotation, currentPosition[0] + 1, currentPosition[1]))
			return;
		currentPosition[0]++;
		resetTimer();
	}
	
	void rotateLeft()
	{
		if (tryRotate((currentRotation + 3) % 4))
			resetTimer();
	}
	
	void rotateRight()
	{
		if (tryRotate((currentRotation + 1) % 4))
			resetTimer();
	}
	
	void holdPiece()
	{
		if (held)
			return;
		held = true;
		if (heldTetromino == Tetromino.None)
		{
			heldTetromino = currentTetromino;
			nextTetromino();
		}
		else
		{
			auto swap = heldTetromino;
			heldTetromino = currentTetromino;
			currentTetromino = swap;
			currentRotation = 0;
			currentPosition = cast(byte[2]) [VirtualWidth / 2 - rotations[currentTetromino][0].length / 8, -FieldOffsetY];
			if (collides(currentTetromino, currentRotation, currentPosition[0], currentPosition[1]))
				gameover = true;
		}
	}
	
	void hardDrop()
	{
		while (!collides(currentTetromino, currentRotation, currentPosition[0], currentPosition[1] + 1))
		{
			currentPosition[1]++;
		}
		forcePlace();
	}
	
	void softDrop()
	{
		if (collides(currentTetromino, currentRotation, currentPosition[0], currentPosition[1] + 1))
			return;
		currentPosition[1]++;
	}
	
	bool tryRotate(ubyte newRot)
	{
		if (!collides(currentTetromino, newRot, currentPosition[0], currentPosition[1]))
		{
			currentRotation = newRot;
		}
		else if (!collides(currentTetromino, newRot, currentPosition[0], currentPosition[1] + 1))
		{
			currentPosition[1]++;
			currentRotation = newRot;
		}
		else if (!collides(currentTetromino, newRot, currentPosition[0], currentPosition[1] - 1))
		{
			currentPosition[1]--;
			currentRotation = newRot;
		}
		else if (!collides(currentTetromino, newRot, currentPosition[0] + 1, currentPosition[1]))
		{
			currentPosition[0]++;
			currentRotation = newRot;
		}
		else if (!collides(currentTetromino, newRot, currentPosition[0] - 1, currentPosition[1]))
		{
			currentPosition[0]--;
			currentRotation = newRot;
		}
		else if (!collides(currentTetromino, newRot, currentPosition[0], currentPosition[1] - 2))
		{
			currentPosition[1] -= 2;
			currentRotation = newRot;
		}
		else return false;
		return true;
	}
	
	void refreshTetrominos()
	{
		while (nextTetrominos.length < 7)
		{
			randomTetrominos.randomShuffle();
			nextTetrominos ~= randomTetrominos;
		}
	}
	
	void tryPlace()
	{
		if (!collides(currentTetromino, currentRotation, currentPosition[0], currentPosition[1] + 1))
			return;
		if (!placeTimerActive)
		{
			placeTimerActive = true;
			placeTimer.reset();
			placeTimer.start();
		}
		else if (placeTimer.peek.to!("msecs", int) >= 200)
		{
			forcePlace();
		}
	}
	
	void forcePlace()
	{
		held = false;
		placeTimerActive = false;
		placeTimer.stop();
		placeTimer.reset();
		const col = collision(currentTetromino, currentRotation);
		for (ubyte y = 0; y < col.length; y++)
			for (ubyte x = 0; x < col[y].length; x++)
				if (col[y][x] == 1)
				{
					assert(field[currentPosition[1] + y][currentPosition[0] + x] == 0);
					field[currentPosition[1] + y][currentPosition[0] + x] = cast(ubyte) (currentTetromino + 1);
				}
		clearLines();
		nextTetromino();
	}
	
	void nextTetromino()
	{
		currentTetromino = nextTetrominos[0];
		nextTetrominos = nextTetrominos[1 .. $];
		currentRotation = 0;
		currentPosition = cast(byte[2]) [VirtualWidth / 2 - rotations[currentTetromino][0].length / 8, -FieldOffsetY];
		if (collides(currentTetromino, currentRotation, currentPosition[0], currentPosition[1]))
			gameover = true;
	}
	
	bool isSolid(X, Y)(X x, Y y) const
	{
		if (x < 0 || x >= VirtualWidth)
			return true;
		if (y >= VirtualHeight)
			return true;
		if (y < 0)
			return false;
		return field[y][x] != 0;
	}
	
	bool collides(X, Y)(Tetromino tetromino, ubyte rotation, X posX, Y posY) const
	{
		const col = collision(tetromino, rotation);
		for (ubyte y = 0; y < col.length; y++)
			for (ubyte x = 0; x < col[y].length; x++)
				if (col[y][x] == 1)
					if (isSolid(posX + x, posY + y))
						return true;
		return false;
	}
	
	static immutable(ubyte[])[] collision(ubyte tetromino, ubyte rotation)
	{
		assert(rotation >= 0 && rotation < 4);
		auto allRots = rotations[tetromino];
		immutable(ubyte[])[] ret;
		foreach(ref line; allRots)
		{
			immutable stride = line.length / 4;
			ret ~= line[rotation * stride .. rotation * stride + stride];
		}
		return ret;
	}
	
	void clearLines()
	{
		for (int y = VirtualHeight - 1; y >= 0; y--)
		{
			bool isCleared = true;
			for (int x = 0; x < VirtualWidth; x++)
			{
				if (field[y][x] == 0)
					isCleared = false;
			}
			if (isCleared)
			{
				for (int yy = y; yy >= 1; yy--)
					field[yy] = field[yy - 1][];
				field[0][] = 0;
				y++;
				cleared++;
			}
		}
	}
	
	void resetTimer()
	{
		placeTimer.stop();
		placeTimer.reset();
		placeTimer.start();
	}
	
	int tickTime()
	{
		if (level <= 16)
			return 300 - level * level;
		else if (level == 17)
			return 30;
		else if (level == 18)
			return 29;
		else if (level == 19)
			return 28;
		else if (level == 20)
			return 26;
		else if (level == 21)
			return 23;
		else if (level == 22)
			return 20;
		else if (level == 23)
			return 16;
		else if (level == 24)
			return 12;
		else
			return 8;
	}
	
	int cleared = 0;
	ubyte level = StartLevel;
	StopWatch updateTimer;
	StopWatch placeTimer;
	bool placeTimerActive;
	bool gameover;
	bool held = false;
	Tetromino currentTetromino;
	Tetromino heldTetromino;
	byte[2] currentPosition;
	ubyte currentRotation;
	ubyte[VirtualWidth][VirtualHeight] field;
	Tetromino[] nextTetrominos;
	Tetromino[] randomTetrominos = [Tetromino.I, Tetromino.L, Tetromino.J, Tetromino.T, Tetromino.S, Tetromino.Z, Tetromino.O];
}

void drawPiece(ref CHAR_INFO[Width * Height] consoleBuffer, Tetromino tetromino, ubyte rotation, int targetX, int targetY, CHAR_INFO color) {
	const col = Game.collision(tetromino, rotation);
	for (int y = col.length - 1; y >= 0; y--)
		for (int x = 0; x < col[y].length; x++)
			if (col[y][x] == 1)
			{
				int displayY = targetY + y;
				int displayX = targetX + x;
				if (displayY > 0)
					consoleBuffer[Width * displayY + 1 + displayX] = color;
			}
}

void cls( HANDLE hConsole )
{
	COORD coordScreen = { 0, 0 };
	BOOL bSuccess;
	DWORD cCharsWritten;
	CONSOLE_SCREEN_BUFFER_INFO csbi; 
	DWORD dwConSize;

	bSuccess = GetConsoleScreenBufferInfo(hConsole, &csbi);
	if (!bSuccess)
		return;
	dwConSize = csbi.dwSize.X * csbi.dwSize.Y;

	bSuccess = FillConsoleOutputCharacterA(hConsole, ' ', dwConSize, coordScreen, &cCharsWritten);
	if (!bSuccess)
		return;

	bSuccess = GetConsoleScreenBufferInfo(hConsole, &csbi);
	if (!bSuccess)
		return;

	bSuccess = FillConsoleOutputAttribute(hConsole, csbi.wAttributes, dwConSize, coordScreen, &cCharsWritten);
	if (!bSuccess)
		return;

	bSuccess = SetConsoleCursorPosition(hConsole, coordScreen);
	if (!bSuccess)
		return;
}

void main() {
	wHnd = GetStdHandle(STD_OUTPUT_HANDLE);
	rHnd = GetStdHandle(STD_INPUT_HANDLE);
	
	auto controls = parseJSON(fs.readText("controls.json"));
	auto key_hold = controls["hold"].integer;
	auto key_hardDrop = controls["hard drop"].integer;
	auto key_softDrop = controls["soft drop"].integer;
	auto key_spinL = controls["spin left"].integer;
	auto key_spinR = controls["spin right"].integer;
	auto key_moveL = controls["move left"].integer;
	auto key_moveR = controls["move right"].integer;
	
	cls(wHnd);

	SetConsoleTitleA("Tetris".toStringz);

	SMALL_RECT windowSize = {0, 0, Width - 1, Height - 1};
	SetConsoleWindowInfo(wHnd, TRUE, &windowSize);

	COORD bufferSize = {Width, Height};
	SetConsoleScreenBufferSize(wHnd, bufferSize);
	
	Game game;

	black.AsciiChar = ' ';
	black.Attributes = FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY;
	hDivider.AsciiChar = '-';
	hDivider.Attributes = FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY;
	vDivider.AsciiChar = '|';
	vDivider.Attributes = FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY;
	dividerCross.AsciiChar = '+';
	dividerCross.Attributes = FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY;
	white.AsciiChar = ' ';
	white.Attributes =
			BACKGROUND_BLUE |
			BACKGROUND_GREEN |
			BACKGROUND_RED |
			BACKGROUND_INTENSITY;
	gray.AsciiChar = '#';
	gray.Attributes =
			FOREGROUND_INTENSITY;
	// I, L, J, T, S, Z, O
	tetrominoColor[Tetromino.I].AsciiChar = ' ';
	tetrominoColor[Tetromino.I].Attributes =
			BACKGROUND_BLUE |
			BACKGROUND_INTENSITY;
	tetrominoColor[Tetromino.L].AsciiChar = ' ';
	tetrominoColor[Tetromino.L].Attributes =
			BACKGROUND_RED |
			BACKGROUND_GREEN;
	tetrominoColor[Tetromino.J].AsciiChar = ' ';
	tetrominoColor[Tetromino.J].Attributes =
			BACKGROUND_BLUE;
	tetrominoColor[Tetromino.T].AsciiChar = ' ';
	tetrominoColor[Tetromino.T].Attributes =
			BACKGROUND_BLUE |
			BACKGROUND_RED;
	tetrominoColor[Tetromino.S].AsciiChar = ' ';
	tetrominoColor[Tetromino.S].Attributes =
			BACKGROUND_GREEN |
			BACKGROUND_INTENSITY;
	tetrominoColor[Tetromino.Z].AsciiChar = ' ';
	tetrominoColor[Tetromino.Z].Attributes =
			BACKGROUND_RED |
			BACKGROUND_INTENSITY;
	tetrominoColor[Tetromino.O].AsciiChar = ' ';
	tetrominoColor[Tetromino.O].Attributes =
			BACKGROUND_RED |
			BACKGROUND_GREEN |
			BACKGROUND_INTENSITY;
	tetrominoColor[Tetromino.None].AsciiChar = ' ';
			
	CHAR_INFO[Width * Height] consoleBuffer;
	consoleBuffer[] = black;
	for (int i = 1; i < Height - 1; i++)
	{
		consoleBuffer[Width * i] = vDivider;
		consoleBuffer[Width * i + 11] = vDivider;
		consoleBuffer[Width * i + 13] = vDivider;
		consoleBuffer[Width * i + 18] = vDivider;
	}
	consoleBuffer[0] = dividerCross;
	consoleBuffer[11] = dividerCross;
	consoleBuffer[13] = dividerCross;
	consoleBuffer[18] = dividerCross;
	consoleBuffer[Width * (Height - 1)] = dividerCross;
	consoleBuffer[Width * (Height - 1) + 11] = dividerCross;
	consoleBuffer[Width * 18 + 13] = dividerCross;
	consoleBuffer[Width * 18 + 18] = dividerCross;
	consoleBuffer[1 .. 11] = hDivider;
	consoleBuffer[Width * (Height - 1) + 1 .. Width * (Height - 1) + 11] = hDivider;
	consoleBuffer[14 .. 18] = hDivider;
	consoleBuffer[Width * 5 + 14 .. Width * 5 + 18] = hDivider;
	consoleBuffer[Width * 6 + 14 .. Width * 6 + 18] = hDivider;
	consoleBuffer[Width * 10 + 14 .. Width * 10 + 18] = hDivider;
	consoleBuffer[Width * 14 + 14 .. Width * 14 + 18] = hDivider;
	consoleBuffer[Width * 18 + 14 .. Width * 18 + 18] = hDivider;
	consoleBuffer[Width * (Height - 1) + 13].AsciiChar = 'L';
	consoleBuffer[Width * (Height - 1) + 14].AsciiChar = 'V';
	consoleBuffer[Width * (Height - 1) + 15].AsciiChar = 'L';
	consoleBuffer[Width * (Height - 1) + 17].AsciiChar = '0' + (game.level / 10);
	consoleBuffer[Width * (Height - 1) + 18].AsciiChar = '0' + (game.level % 10);

	//   0    5   10   15   20
	//   v    v    v    v    v
	// 0>+----------+ +----+
	//  >|          | |    |
	//  >|          | |####|
	//  >|          | |    |
	//  >|          | |    |
	// 5>|          | |----|
	//  >|          | |----|
	//  >|          | |#   |
	//  >|          | |### |
	//  >|          | |    |
	//10>|          | |----|
	//  >|          | |  # |
	//  >|          | |### |
	//  >|          | |    |
	//  >|          | |----|
	//15>|          | |##  |
	//  >|          | |##  |
	//  >|          | |    |
	//  >|          | +----+
	//  >+----------+ LVL 01
	//20
	
	COORD charBufSize = {Width, Height};
	COORD characterPos = {0, 0};
	SMALL_RECT gameDrawArea = {0, 0, Width - 1, Height - 1};

	DWORD numEvents = 0;
	DWORD numEventsRead = 0;
	
	version (AutoPlay)
	{
		StopWatch turnWatch;
		turnWatch.start();
	}
	
	StopWatch inputWatch;
	inputWatch.start();

	game.start();
	bool running = true;
	bool paused = false;
	
	bool softDrop = false;
	bool left, right;
	int holdFrames = 0;
	
	while (running) {
		GetNumberOfConsoleInputEvents(rHnd, &numEvents);

		if (!paused)
			game.update();
		
		if (game.cleared >= min(10, game.level * 5)) {
			game.cleared -= min(10, game.level * 5);
			game.level++;
			consoleBuffer[Width * (Height - 1) + 17].AsciiChar = '0' + (game.level / 10);
			consoleBuffer[Width * (Height - 1) + 18].AsciiChar = '0' + (game.level % 10);
		}
		
		for (int y = 1; y < 19; y++)
			consoleBuffer[Width * y + 1 .. Width * y + 11] = black;
		
		for (int y = VirtualHeight - 1; y >= 0; y--)
		{
			int displayY = y + FieldOffsetY;
			if (displayY >= 1)
				for (int x = 0; x < VirtualWidth; x++)
					if (game.field[y][x] > 0)
						consoleBuffer[Width * displayY + 1 + x] = tetrominoColor[game.field[y][x] - 1];
		}
		
		int harddropOffset = 0;
		while (!game.collides(game.currentTetromino, game.currentRotation, game.currentPosition[0], game.currentPosition[1] + harddropOffset))
			harddropOffset++;
		consoleBuffer.drawPiece(game.currentTetromino, game.currentRotation, game.currentPosition[0], game.currentPosition[1] + FieldOffsetY + harddropOffset - 1, gray);
		
		consoleBuffer.drawPiece(game.currentTetromino, game.currentRotation, game.currentPosition[0], game.currentPosition[1] + FieldOffsetY, tetrominoColor[game.currentTetromino]);
		
		for (int y = 1; y < 5; y++)
			consoleBuffer[Width * y + 14 .. Width * y + 18] = black;
		for (int y = 7; y < 10; y++)
			consoleBuffer[Width * y + 14 .. Width * y + 18] = black;
		for (int y = 11; y < 14; y++)
			consoleBuffer[Width * y + 14 .. Width * y + 18] = black;
		for (int y = 15; y < 18; y++)
			consoleBuffer[Width * y + 14 .. Width * y + 18] = black;
		if (game.heldTetromino != Tetromino.None)
			consoleBuffer.drawPiece(game.heldTetromino, 0, 13, 1, tetrominoColor[game.heldTetromino]);
		for (int i = 0; i < 3; i++)
			consoleBuffer.drawPiece(game.nextTetrominos[i], 0, 13, 7 + i * 4, tetrominoColor[game.nextTetrominos[i]]);
			
		if (paused)
		{
			for (int i = 3; i <= 8; i++)
				consoleBuffer[Width * 8 + i].Attributes = FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY;
			consoleBuffer[Width * 8 + 3].AsciiChar = 'P';
			consoleBuffer[Width * 8 + 4].AsciiChar = 'A';
			consoleBuffer[Width * 8 + 5].AsciiChar = 'U';
			consoleBuffer[Width * 8 + 6].AsciiChar = 'S';
			consoleBuffer[Width * 8 + 7].AsciiChar = 'E';
			consoleBuffer[Width * 8 + 8].AsciiChar = 'D';
		}
		else if (inputWatch.peek.to!("msecs", int) > 20)
		{
			inputWatch.reset();
			inputWatch.start();
			if (softDrop)
				game.softDrop();
			if (left || right)
				holdFrames++;
			if (left)
			{
				if (holdFrames > HoldThreshold)
					game.moveLeft();
			}
			else if (right)
			{
				if (holdFrames > HoldThreshold)
					game.moveRight();
			}
			else holdFrames = 0;
		}
		
		WriteConsoleOutputA(wHnd, consoleBuffer.ptr, charBufSize, characterPos, &gameDrawArea);
		
		version (AutoPlay)
		{
			if (!paused && turnWatch.peek.to!("msecs", int) > 10)
			{
				turnWatch.reset();
				turnWatch.start();
				if (uniform(0, 4) == 0)
				{
					if (uniform(0, 2) == 1)
						game.moveLeft();
					else
						game.moveRight();
				}
				if (uniform(0, 16) == 0)
				{
					if (uniform(0, 2) == 1)
						game.rotateLeft();
					else
						game.rotateRight();
				}
			}
		}
		
		if (numEvents != 0) {
			INPUT_RECORD[] eventBuffer = new INPUT_RECORD[numEvents];
			ReadConsoleInputA(rHnd, eventBuffer.ptr, numEvents, &numEventsRead);

			foreach (event; eventBuffer[0 .. numEventsRead]) {
				if (event.EventType == KEY_EVENT) {
					if (event.KeyEvent.bKeyDown) {
						if (event.KeyEvent.wVirtualKeyCode == VK_ESCAPE)
							paused = !paused;
						if (paused)
							continue;
						if (event.KeyEvent.wVirtualKeyCode == key_moveL) {
							game.moveLeft();
							left = true;
						}
						else if (event.KeyEvent.wVirtualKeyCode == key_moveR) {
							game.moveRight();
							right = true;
						}
						else if (event.KeyEvent.wVirtualKeyCode == key_spinL) {
							game.rotateLeft();
						}
						else if (event.KeyEvent.wVirtualKeyCode == key_spinR) {
							game.rotateRight();
						}
						else if (event.KeyEvent.wVirtualKeyCode == key_hold) {
							game.holdPiece();
						}
						else if (event.KeyEvent.wVirtualKeyCode == key_hardDrop) {
							game.hardDrop();
						}
						else if (event.KeyEvent.wVirtualKeyCode == key_softDrop) {
							softDrop = true;
						}
					}
					else {
						if (event.KeyEvent.wVirtualKeyCode == key_softDrop)
							softDrop = false;
						else if (event.KeyEvent.wVirtualKeyCode == key_moveL)
							left = false;
						else if (event.KeyEvent.wVirtualKeyCode == key_moveR)
							right = false;
					}
				}
			}
		}
		
		
	}
}