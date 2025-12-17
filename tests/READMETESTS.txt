TUTORIAL PARA EJECUTAR LOS TESTS:

*Arrancar el GSC

iex -S mix --> MSAPI ya arranca el GSC

*Lanzar los clientes:

Varios a la vez
python test_mocks/start_test.py 

Uno a uno
python test_mocks/mock_client.py --name Player1
python test_mocks/mock_client.py --name Player2
